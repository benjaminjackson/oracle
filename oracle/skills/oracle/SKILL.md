---
name: oracle
description: Ask the Oracle — a one-shot Fable answer from a stripped headless session (~1.3k tokens of overhead vs ~6k for the oracle subagent), or, only when the user asks for Gemini, a one-shot Gemini 4 Neon answer. Use when the user says "ask the oracle", "oracle,", or "/oracle <question>". Also use when the user says "ask Gemini", "gemini oracle", or "/oracle --gemini <question>".
---

Send the question to a bare headless Fable session, then present its answer to the user in your own words, along with the token/cost stats for that call.

Fable is the default. Use Gemini 4 Neon only when the user asks for it: "ask Gemini", "gemini oracle", or `/oracle --gemini <question>`. In that case do step 1 below, then follow "Gemini path" in place of step 2.

Never put a heredoc inside `$(...)` (i.e. `q=$(cat <<'EOF' ... EOF)`). On macOS's stock `/bin/bash` (3.2 — an old pre-GPLv3 build Apple never upgraded), a heredoc nested in a command substitution breaks the parser the instant the body contains a single quote (`don't`, `it's`, any contraction) — `unexpected EOF while looking for matching`. It's a real bash 3.2 bug, not a wording problem, and it reproduces even for a one-word heredoc; it doesn't happen in zsh or bash 4+, which is why it's intermittent depending on what's invoking the script.

Instead, write the question to a plain text file with the Write tool (no shell parsing of the content at all, so quotes/backticks/`$` are inert), then read it back with a bare `$(cat file)` — safe because there's no heredoc involved.

1. Write the question, plus only the minimal context Oracle needs, to `<scratchpad>/oracle_question.txt` (use your actual scratchpad path) with the Write tool — plain text, no heredoc, no escaping.

2. Run with the Bash tool:

```bash
Q=<scratchpad>/oracle_question.txt
mode=--safe-mode
if [ -n "$ANTHROPIC_API_KEY" ]; then mode=--bare; fi
out=$(claude -p $mode --model fable --output-format json --tools "WebSearch" --allowedTools "WebSearch" < /dev/null \
  --system-prompt "$(cat "${CLAUDE_SKILL_DIR}/system_prompt.txt")" \
  "$(cat "$Q")")
printf '%s\n' "$out" | jq -r '.result'
printf '%s\n' "$out" | jq -r '(.usage.input_tokens + .usage.cache_creation_input_tokens + .usage.cache_read_input_tokens) as $in | (.total_cost_usd * 1000000 | round / 1000000) as $cost | "[\($in) in / \(.usage.output_tokens) out tokens · $\($cost)]"'
```

Notes: `--tools "WebSearch"` stays unconditional — the schema costs a measured ~600 input tokens (evals Phase 0), which is noise; omitting the flag loads the CLI's ~17k-token default toolset instead. `< /dev/null` is required — `claude -p` otherwise stalls 3s waiting for stdin and prints a warning into the output. `--bare` (API key, off-quota) is used when `ANTHROPIC_API_KEY` is set, else `--safe-mode` (OAuth, on-quota). `--output-format json` is required to get cost/usage data back instead of plain text; the two `jq` calls split the JSON into the answer line and the stats line. `printf '%s\n'` feeds them, not `echo`: zsh's `echo` turns the `\n` inside the JSON into real newlines, and `jq` then rejects the JSON. The system prompt is in `system_prompt.txt` next to this file, so the Fable path and the Gemini path send the same text.

## Gemini path

Only when the user asks for Gemini. Write the question file as in step 1, then run with the Bash tool:

```bash
"${CLAUDE_SKILL_DIR}/gemini_oracle.sh" <scratchpad>/oracle_question.txt
```

The script sends the question to Gemini 4 Neon (`gemini-4-neon`) through Google's Interactions API, with the same Oracle system prompt and with Google Search in place of WebSearch. It prints the answer, then a stats line such as `[447 in / 205 out + 681 thinking tokens · $0.009754 + 5 searches (free in the first 5000 per month, else $0.07)]`. The part after `+` is there only when Gemini searched.

- It needs `GEMINI_API_KEY` in the environment. Never print or read the key value. If the script says the key is not set, tell the user to export it and stop.
- No API response from Google has a price in it. The script calculates the cost from the token counts and the prices that `gemini_price.sh` reads from Google's pricing page (cached for 24 hours in `~/.cache/oracle/`). If that lookup fails, the stats line says `cost unknown`. Show it as it is. Never fill in a price yourself.
- The first dollar amount is the token cost. Google bills searches apart from tokens: a fee per search, after a free monthly allowance. No API says how much of the allowance is left, so the script cannot know if a search was billed. The stats line gives the search fee as a second amount: what the searches cost if the allowance is used up. Do not add the two amounts together, and do not drop the search part. If the fee cannot be read from the pricing page, the line says `fee unknown`.
- If the script fails, show Google's error message to the user and stop. Do not fall back to the `oracle` subagent and do not fall back to Fable: subagents run only Claude models, and the user asked for Gemini. A 429 error that names `free_tier` means that billing is off for the key's project, or that the key is the wrong one.
- The rules below about the question file and about rewriting the answer apply to this path too. Every token in the file is billed by Google.

Rules:
- Every token in `oracle_question.txt` is Fable-priced. Pass the question and the few lines of context it genuinely needs — never file dumps or conversation history.
- Oracle can search the web but has no file access. If the question needs a file's contents, read the file first and paste the relevant lines into `oracle_question.txt`.
- Rewrite Oracle's answer in your own words before presenting it — keep every fact, number, caveat, and recommendation intact, and do not add anything it did not say or pad it out longer than the original. Follow it, on its own line, with the stats line the script prints (`[N in / M out tokens · $X]`, or the longer Gemini form) unchanged.
- If the Fable command fails (auth, sandbox), fall back to the `oracle` subagent via the Agent tool and note the fallback costs ~6k tokens. This fallback is for the Fable path only.
