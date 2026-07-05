#!/usr/bin/env bash
# One generation call: run_one.sh <config-id> <question-id> <repeat>
# Question text goes to claude -p via stdin (quote-safe; avoids bash-3.2 heredoc
# bug and the variadic --tools flag swallowing a positional prompt).
set -u
cd "$(dirname "$0")"
cfg=$1 qid=$2 rep=$3
out_file="results/raw/${cfg}__${qid}__r${rep}.json"

cline=$(jq -c --arg id "$cfg" 'select(.id==$id)' configs.jsonl)
[ -n "$cline" ] || { echo "FAIL $cfg $qid r$rep (no such config)" >&2; exit 1; }
prompt=$(printf '%s' "$cline" | jq -r '.prompt')
effort=$(printf '%s' "$cline" | jq -r '.effort // empty')
tools=$(printf '%s' "$cline" | jq -r '.tools')

qtmp=$(mktemp)
jq -r --arg id "$qid" 'select(.id==$id).q' questions.jsonl > "$qtmp"
[ -s "$qtmp" ] || { echo "FAIL $cfg $qid r$rep (no such question)" >&2; rm -f "$qtmp"; exit 1; }

mode=--safe-mode
[ -n "${ANTHROPIC_API_KEY:-}" ] && mode=--bare

out=$(claude -p $mode --model fable --output-format json \
  ${effort:+--effort "$effort"} \
  --tools "$tools" --allowedTools "$tools" \
  --system-prompt "$prompt" < "$qtmp" 2>/dev/null)
rm -f "$qtmp"

if printf '%s' "$out" | jq -e '(.result != null) and (.is_error != true)' > /dev/null 2>&1; then
  printf '%s' "$out" | jq -c --arg config "$cfg" --arg qid "$qid" --argjson rep "$rep" \
    '{config:$config, qid:$qid, repeat:$rep, answer:.result, num_turns:.num_turns,
      duration_ms:.duration_ms, usage:.usage, total_cost_usd:.total_cost_usd}' \
    > "$out_file.tmp" && mv "$out_file.tmp" "$out_file"
  echo "ok   $cfg $qid r$rep"
else
  echo "FAIL $cfg $qid r$rep" >&2
  exit 1
fi
