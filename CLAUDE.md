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
oracle/agents/oracle.md            # fallback subagent, used only if the shell-out fails
evals/                             # eval harness (shared scripts) + evals/experiments/<name>/ (data + results)
```

## How oracle actually works

The skill (`oracle/skills/oracle/SKILL.md`) writes the question to a scratch
file with the Write tool — never inline via a heredoc inside `$(...)`, since
bash 3.2 on macOS breaks on contractions in that construct — then runs:

```
claude -p $mode --model fable --output-format json \
  --tools "WebSearch" --allowedTools "WebSearch" \
  --system-prompt "<Oracle persona>" < /dev/null \
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
