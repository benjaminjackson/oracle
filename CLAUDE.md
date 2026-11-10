# oracle

Claude Code plugin marketplace repo shipping one plugin, `oracle`: a
cheap-as-possible way to get a one-shot answer from a fresh model (Fable)
with no conversation history, invoked as a skill (cheap path) with an agent
fallback (robust, pricier path).

## Layout

```
.claude-plugin/marketplace.json    # marketplace manifest, points at ./oracle
oracle/.claude-plugin/plugin.json  # oracle plugin manifest
oracle/skills/oracle/SKILL.md      # default path: shells out to headless `claude -p`
oracle/skills/oracle/system_prompt.txt  # the Oracle persona; both skill paths send this file
oracle/skills/oracle/gemini_oracle.sh   # opt-in Gemini 4 Carbon path: one call to Google's Interactions API
oracle/skills/oracle/gemini_price.sh    # reads Gemini prices from Google's pricing page, fails closed
oracle/agents/oracle.md            # fallback subagent, used only if the Fable shell-out fails
evals/                             # eval harness (shared scripts) + evals/experiments/<name>/ (data + results)
```

## How oracle actually works

The skill (`oracle/skills/oracle/SKILL.md`) writes the question to a scratch
file with the Write tool — never inline via a heredoc inside `$(...)`, since
bash 3.2 on macOS breaks on contractions in that construct — then runs:

```
claude -p $mode --model fable --output-format json \
  --tools "WebSearch" --allowedTools "WebSearch" \
  --system-prompt "$(cat system_prompt.txt)" < /dev/null \
  "$(cat "$Q")"
```

- `$mode` is `--bare` (API billing, off Claude Code subscription quota) if
  `ANTHROPIC_API_KEY` is set, else `--safe-mode` (OAuth, on-quota).
- `--tools "WebSearch"` is kept **unconditional** — its schema only costs
  ~600 input tokens, while omitting `--tools` entirely pulls in the CLI's
  full default toolset at ~17k tokens (measured in Phase 0, see
  `evals/experiments/prompt-tuning-2026-07/README.md`).
- `--output-format json` is required to pull `usage`/`total_cost_usd` back
  out via `jq`, so the skill can report tokens + cost alongside the answer.
- The system prompt casts the model as "Oracle": a terse, telegraphic
  persona (shorthand notation, no filler) — this is the `p6-shorthand`
  config that won the prompt-tuning experiment on quality at neutral token
  cost, not the original prompt.
- Oracle has no file access beyond WebSearch — the caller pastes any needed
  file contents into the question file itself.

The agent (`oracle/agents/oracle.md`) is a fallback only: same persona,
`model: fable`, tools `Read, Grep, Glob, WebSearch, WebFetch`, invoked when
the skill's shell-out fails (no `claude` CLI on PATH, broken auth, sandboxed
environment). It costs roughly 6k tokens/question vs ~200 for the skill —
strictly worse but works when the cheap path can't run at all.

## The Gemini path (opt-in)

Fable is the default. When the user says "ask Gemini", "gemini oracle", or
`/oracle --gemini <question>`, the skill runs `gemini_oracle.sh <question
file>` in place of the `claude -p` command. The question file is written the
same way.

- The script calls `POST /v1beta/interactions` (the Interactions API, with the
  header `Api-Revision: 2026-05-20`) for model `gemini-4-carbon`. It sends
  `system_prompt.txt` as `system_instruction`, the tool
  `{"type":"google_search"}`, and `store: false`. The thinking level is
  Google's default.
- It needs `GEMINI_API_KEY` in the environment. The key goes to curl through
  `--header @<(printf ...)`, so it is not on a command line. Never print it.
- The answer is the text of the `model_output` items in the response's
  `steps` array. Token counts are in `usage`.
- **No Google response has a price in it.** Cost = tokens x price, and
  `gemini_price.sh` reads the price from
  `https://aistudio.google.com/docs/pricing.md` (the "Standard" tab of the
  Gemini 4 Carbon section, paid tier column). The page copy is in
  `~/.cache/oracle/gemini-pricing.md` and is downloaded again when it is more
  than 24 hours old. Price cells have dates in them ("$2.00 through November
  30, 2026. $4.00 starting December 1, 2026."), and the script picks the
  price for today.
- **The price script fails closed.** If the page is not exactly as expected,
  it exits non-zero and the stats line says `cost unknown`. Never add a
  hard-coded or fallback price. When Google changes the page, the correct fix
  is to update the parser, with a test for the new shape.
- Cost formula, checked against real responses: `(input - cached) x input
  price + cached x caching price + (output + thinking) x output price`.
  Cached tokens are a part of `total_input_tokens`. If `usage` is absent,
  does not add up, or reports tool-use tokens, the cost is `cost unknown`.
- Google Search is billed per search after 5,000 free searches per month, and
  no API reports how much of that allowance is left. So the stats line shows
  the search fee as a second amount ("free in the first 5000 per month, else
  $X"), never added to the token cost. `gemini_price.sh --search-fee` reads
  the fee from the same page.
- **No fallback.** On an API error the script prints Google's error and
  exits non-zero. The `oracle` subagent runs only Claude models, so it cannot
  stand in for Gemini.
- Both scripts must run on macOS stock `/bin/bash` 3.2.
- The eval for this path is `evals/experiments/gemini-carbon-2026-11/`. A
  config with `"provider":"gemini"` in `configs.jsonl` makes `run_one.sh`
  call `gemini_oracle.sh --json`. Unlike the Fable path on a subscription,
  every Gemini eval call is billed.

## evals/ — the eval harness

`evals/` holds a bash+jq harness shared across every prompt-tuning
experiment, plus `evals/experiments/<name>/` folders that each hold one
experiment's question corpus, config matrix, and results. See
`evals/README.md` for full script docs and `evals/experiments/*/README.md`
for each experiment's results/decision log — the current one is
`evals/experiments/prompt-tuning-2026-07/`, which tuned Oracle's
`--effort` × system-prompt configuration and landed on the shorthand
prompt now shipping in `SKILL.md`/`oracle.md`.

Key mechanic to know before touching any of these scripts: they all operate
on the **current working directory**, not the script's own directory —
`cd` into an experiment folder before invoking them (e.g. `cd
evals/experiments/prompt-tuning-2026-07 && ../../summary.sh`). This is what
lets one shared set of scripts serve any number of experiment folders.
Starting a new experiment means creating a new folder under
`evals/experiments/` with its own `configs.jsonl` + `questions.jsonl`, `cd`
into it, and run the same scripts.

## HANDOFF.md

Untracked scratch doc (a "just the facts" brief prepared to hand off to
Fable for eval design) — not part of the committed repo, but useful
background if present: documents Fable pricing/caching mechanics, confirmed
CLI flags, and six open questions about Oracle's cost/quality tradeoffs
(model tier, `--effort`, brief-reasoning prompting, forced single-token
answers, whether caching actually helps given Oracle's one-off call
pattern, and whether any combination dominates). Most of these were since
answered by the `prompt-tuning-2026-07` experiment; check that experiment's
README before assuming a question in HANDOFF.md is still open.
