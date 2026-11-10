#!/usr/bin/env bash
# One generation call: run_one.sh <config-id> <question-id> <repeat>
# Question text goes to claude -p via stdin (quote-safe; avoids bash-3.2 heredoc
# bug and the variadic --tools flag swallowing a positional prompt).
set -u
case "${1:-}" in
  -h|--help) echo "usage: run_one.sh <config-id> <question-id> <repeat>" >&2; exit 0 ;;
esac
cfg=$1 qid=$2 rep=$3
out_file="results/raw/${cfg}__${qid}__r${rep}.json"

cline=$(jq -c --arg id "$cfg" 'select(.id==$id)' configs.jsonl)
[ -n "$cline" ] || { echo "FAIL $cfg $qid r$rep (no such config)" >&2; exit 1; }
prompt=$(printf '%s' "$cline" | jq -r '.prompt')
effort=$(printf '%s' "$cline" | jq -r '.effort // empty')
tools=$(printf '%s' "$cline" | jq -r '.tools')
# A config with "provider":"gemini" goes to Gemini 4 Carbon. Any other config goes to claude -p.
provider=$(printf '%s' "$cline" | jq -r '.provider // "claude"')

qtmp=$(mktemp)
jq -r --arg id "$qid" 'select(.id==$id).q' questions.jsonl > "$qtmp"
[ -s "$qtmp" ] || { echo "FAIL $cfg $qid r$rep (no such question)" >&2; rm -f "$qtmp"; exit 1; }

if [ "$provider" = "gemini" ]; then
  # The skill's own script makes the call, so the eval measures what ships.
  # Its --json output already has answer, usage.output_tokens and total_cost_usd,
  # which are the fields summary.sh reads. Thinking tokens are in usage.thought_tokens.
  SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  ptmp=$(mktemp)
  printf '%s' "$prompt" > "$ptmp"
  out=$("$SELF_DIR/../oracle/skills/oracle/gemini_oracle.sh" "$qtmp" --system-prompt-file "$ptmp" --json 2>/dev/null)
  rm -f "$qtmp" "$ptmp"
  if printf '%s' "$out" | jq -e '.answer != null' > /dev/null 2>&1; then
    printf '%s' "$out" | jq -c --arg config "$cfg" --arg qid "$qid" --argjson rep "$rep" \
      '{config:$config, qid:$qid, repeat:$rep, num_turns:1} + .' \
      > "$out_file.tmp" && mv "$out_file.tmp" "$out_file"
    echo "ok   $cfg $qid r$rep"
    exit 0
  fi
  echo "FAIL $cfg $qid r$rep" >&2
  exit 1
fi

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
