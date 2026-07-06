#!/usr/bin/env bash
# One judge call (Sonnet, no tools, structured output).
#   judge_one.sh pw <base> <chall> <qid> <rep> <orient>
#   judge_one.sh anchor <cfg> <qid> <rep>
set -u
cd "$(dirname "$0")"
kind=$1; shift

mode=--safe-mode
[ -n "${ANTHROPIC_API_KEY:-}" ] && mode=--bare

judge_call() { # $1=prompt-file $2=json-schema; echoes CLI json on stdout
  claude -p $mode --model sonnet --output-format json \
    --tools "" --allowedTools "" \
    --json-schema "$2" < "$1" 2>/dev/null
}

# Extract the structured verdict whether .result arrives as object or string.
VERDICT_JQ='.result | if type == "string" then fromjson else . end'

case "$kind" in
  pw)
    base=$1 chall=$2 qid=$3 rep=$4 orient=$5
    out_file="results/judgments/pw__${base}__vs__${chall}__${qid}__r${rep}__o${orient}.json"
    q=$(jq -r --arg id "$qid" 'select(.id==$id).q' questions.jsonl)
    kp=$(jq -r --arg id "$qid" 'select(.id==$id).key_points | map("- " + .) | join("\n")' questions.jsonl)
    base_ans=$(jq -r '.answer' "results/raw/${base}__${qid}__r${rep}.json")
    chall_ans=$(jq -r '.answer' "results/raw/${chall}__${qid}__r${rep}.json")
    if [ "$orient" = "1" ]; then a_ans=$base_ans; b_ans=$chall_ans; a_is=base; else a_ans=$chall_ans; b_ans=$base_ans; a_is=challenger; fi

    ptmp=$(mktemp)
    {
      printf 'You are judging two candidate answers to the same question, written for a busy, smart asker who wants the best decision-relevant answer.\n\nQUESTION:\n%s\n\n' "$q"
      printf 'KEY POINTS a competent answer should get right (not a checklist to count — a guide to what matters):\n%s\n\n' "$kp"
      printf 'ANSWER A:\n%s\n\nANSWER B:\n%s\n\n' "$a_ans" "$b_ans"
      printf 'Rubric:\n- Correctness first: a factual or reasoning error that would mislead the asker is disqualifying.\n- Usefulness: does it land on a clear, actionable answer and cover the key points that matter?\n- Length is NOT merit. Before deciding, name any specific claim, fact, or number the longer answer has that the shorter one lacks. Count it as an advantage only if it is genuinely new and would change what the asker does next -- if it only restates, hedges, or elaborates a point the shorter answer already covers, it is padding, not merit. Example: if two answers reach the same correct conclusion but one adds extra caveats that would not change what the asker does next, those caveats are padding, not an advantage. Do not reward padding, hedging, or exhaustiveness for its own sake.\n- Judge only what is written. Choose "tie" when the answers are genuinely comparable in quality.\n\nGive your reasoning first, then the winner ("A", "B", or "tie").\n'
    } > "$ptmp"

    schema='{"type":"object","properties":{"reason":{"type":"string"},"winner":{"type":"string","enum":["A","B","tie"]}},"required":["reason","winner"]}'
    out=$(judge_call "$ptmp" "$schema"); rm -f "$ptmp"

    if printf '%s' "$out" | jq -e "($VERDICT_JQ) | .winner" > /dev/null 2>&1; then
      printf '%s' "$out" | jq -c --arg base "$base" --arg chall "$chall" --arg qid "$qid" \
        --argjson rep "$rep" --argjson orient "$orient" --arg a_is "$a_is" \
        "($VERDICT_JQ) as \$v |
         {kind:\"pairwise\", base:\$base, challenger:\$chall, qid:\$qid, repeat:\$rep,
          orientation:\$orient, a_is:\$a_is, winner_raw:\$v.winner, reason:\$v.reason,
          winner: (if \$v.winner == \"tie\" then \"tie\"
                   elif (\$v.winner == \"A\") == (\$a_is == \"base\") then \"base\"
                   else \"challenger\" end),
          judge_usage:.usage, judge_cost_usd:.total_cost_usd}" \
        > "$out_file.tmp" && mv "$out_file.tmp" "$out_file"
      echo "ok   pw $chall $qid r$rep o$orient"
    else
      echo "FAIL pw $base vs $chall $qid r$rep o$orient" >&2
      exit 1
    fi
    ;;
  anchor)
    cfg=$1 qid=$2 rep=$3
    out_file="results/judgments/anch__${cfg}__${qid}__r${rep}.json"
    q=$(jq -r --arg id "$qid" 'select(.id==$id).q' questions.jsonl)
    truth=$(jq -r --arg id "$qid" 'select(.id==$id).truth' questions.jsonl)
    ans=$(jq -r '.answer' "results/raw/${cfg}__${qid}__r${rep}.json")

    ptmp=$(mktemp)
    {
      printf 'You are grading a candidate answer against a verified reference answer.\n\nQUESTION:\n%s\n\nREFERENCE (verified correct):\n%s\n\nCANDIDATE ANSWER:\n%s\n\n' "$q" "$truth" "$ans"
      printf 'Mark the candidate correct if it gets the factual core of the reference right. Extra detail, different phrasing, or brevity do not matter; contradicting the reference on the core fact, or omitting it entirely, is incorrect.\n\nGive your reasoning first, then the verdict.\n'
    } > "$ptmp"

    schema='{"type":"object","properties":{"reason":{"type":"string"},"correct":{"type":"boolean"}},"required":["reason","correct"]}'
    out=$(judge_call "$ptmp" "$schema"); rm -f "$ptmp"

    if printf '%s' "$out" | jq -e "($VERDICT_JQ) | has(\"correct\")" > /dev/null 2>&1; then
      printf '%s' "$out" | jq -c --arg cfg "$cfg" --arg qid "$qid" --argjson rep "$rep" \
        "($VERDICT_JQ) as \$v |
         {kind:\"anchor\", config:\$cfg, qid:\$qid, repeat:\$rep,
          correct:\$v.correct, reason:\$v.reason,
          judge_usage:.usage, judge_cost_usd:.total_cost_usd}" \
        > "$out_file.tmp" && mv "$out_file.tmp" "$out_file"
      echo "ok   anchor $cfg $qid r$rep"
    else
      echo "FAIL anchor $cfg $qid r$rep" >&2
      exit 1
    fi
    ;;
  *) echo "judge_one.sh: unknown kind $kind" >&2; exit 1 ;;
esac
