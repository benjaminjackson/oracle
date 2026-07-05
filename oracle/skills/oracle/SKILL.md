---
name: oracle
description: Ask the Oracle — a one-shot Fable answer from a stripped headless session (~1.3k tokens of overhead vs ~6k for the oracle subagent). Use when the user says "ask the oracle", "oracle,", or "/oracle <question>".
---

Send the question to a bare headless Fable session and relay the answer verbatim, along with the token/cost stats for that call.

Never put a heredoc inside `$(...)` (i.e. `q=$(cat <<'EOF' ... EOF)`). On macOS's stock `/bin/bash` (3.2 — an old pre-GPLv3 build Apple never upgraded), a heredoc nested in a command substitution breaks the parser the instant the body contains a single quote (`don't`, `it's`, any contraction) — `unexpected EOF while looking for matching`. It's a real bash 3.2 bug, not a wording problem, and it reproduces even for a one-word heredoc; it doesn't happen in zsh or bash 4+, which is why it's intermittent depending on what's invoking the script.

Instead, write the question to a plain text file with the Write tool (no shell parsing of the content at all, so quotes/backticks/`$` are inert), then read it back with a bare `$(cat file)` — safe because there's no heredoc involved.

1. Write the question, plus only the minimal context Oracle needs, to `<scratchpad>/oracle_question.txt` (use your actual scratchpad path) with the Write tool — plain text, no heredoc, no escaping.

2. Run with the Bash tool:

```bash
Q=<scratchpad>/oracle_question.txt
mode=--safe-mode
if [ -n "$ANTHROPIC_API_KEY" ]; then mode=--bare; fi
out=$(claude -p $mode --model fable --output-format json --tools "WebSearch" --allowedTools "WebSearch" < /dev/null \
  --system-prompt "You are Oracle. Answer as concisely as possible — the shortest response that is still correct and complete. Lead with the answer, in the first word if possible. State it with confidence; flag uncertainty only when it would change what the user does next. When a question is ambiguous, answer the most likely reading. Search the web only when the answer needs facts newer or more specific than your knowledge; otherwise answer directly." \
  "$(cat "$Q")")
echo "$out" | jq -r '.result'
echo "$out" | jq -r '(.usage.input_tokens + .usage.cache_creation_input_tokens + .usage.cache_read_input_tokens) as $in | (.total_cost_usd * 1000000 | round / 1000000) as $cost | "[\($in) in / \(.usage.output_tokens) out tokens · $\($cost)]"'
```

Notes: `< /dev/null` is required — `claude -p` otherwise stalls 3s waiting for stdin and prints a warning into the output. `--bare` (API key, off-quota) is used when `ANTHROPIC_API_KEY` is set, else `--safe-mode` (OAuth, on-quota). `--output-format json` is required to get cost/usage data back instead of plain text; the two `jq` calls split the JSON into the answer line and the stats line.

Rules:
- Every token in `oracle_question.txt` is Fable-priced. Pass the question and the few lines of context it genuinely needs — never file dumps or conversation history.
- Oracle can search the web but has no file access. If the question needs a file's contents, read the file first and paste the relevant lines into `oracle_question.txt`.
- Relay Oracle's answer to the user verbatim, followed on its own line by the stats line the script prints (`[N in / M out tokens · $X]`). Do not expand, soften, re-explain, or reformat either line.
- If the command fails (auth, sandbox), fall back to the `oracle` subagent via the Agent tool and note the fallback costs ~6k tokens.
