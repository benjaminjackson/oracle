#!/usr/bin/env bash
# Blind calibration audit prep: sample N judged pairs, print them with the
# two answers in random order and no config labels, and write the answer key.
#   calibrate.sh [N]           (default 18)
# Human verdicts go in results/calibration_human.tsv as "<pair_id>\tA|B|tie";
# then run: calibrate.sh score
set -u
cd "$(dirname "$0")"

KEY=results/calibration_key.tsv
SHEET=results/calibration_sheet.md

case "${1:-}" in
  -h|--help)
    echo "usage: calibrate.sh [N] [filter]   sample N blind pairs (default 18); filter is an optional challenger regex, e.g. 'caveman'" >&2
    echo "       calibrate.sh score          score results/calibration_human.tsv against the hidden key" >&2
    exit 0
    ;;
esac

if [ "${1:-}" = "score" ]; then
  [ -s results/calibration_human.tsv ] || { echo "fill in results/calibration_human.tsv first (pair_id<TAB>A|B|tie)" >&2; exit 1; }
  join -t "$(printf '\t')" <(sort "$KEY") <(sort results/calibration_human.tsv) | awk -F '\t' '
    # key: pair_id, judge_verdict(base/challenger/tie), a_is(base|challenger), challenger, qid, rep
    # human: A|B|tie -> map through a_is to base/challenger/tie
    {
      human = $7
      if (human == "tie") h = "tie"
      else if ((human == "A") == ($3 == "base")) h = "base"
      else h = "challenger"
      total++
      if (h == $2) agree++
    }
    END { printf "agreement: %d/%d (%.0f%%)\n", agree, total, agree * 100 / total
          if (total > 0 && agree / total < 0.8) print "below ~80% — escalate judge to Opus and re-judge (answers are stored; re-judging is free)" }'
  exit 0
fi

N="${1:-18}"
case "$N" in
  ''|*[!0-9]*) echo "calibrate.sh: N must be a positive integer (got '$N'). Try --help." >&2; exit 1 ;;
esac
FILTER="${2:-.}"   # optional challenger regex, e.g. 'caveman'
mkdir -p results
# Sample from combined pairwise judgments (one per qid/repeat/pair, decisive-or-tie alike)
cat results/judgments/pw__*.json | jq -s -c --arg f "$FILTER" '
  [ group_by([.base, .challenger, .qid, .repeat])[] | select(length == 2) |
    select(.[0].challenger | test($f)) |
    { base: .[0].base, challenger: .[0].challenger, qid: .[0].qid, repeat: .[0].repeat,
      verdict: (if .[0].winner == .[1].winner then .[0].winner else "tie" end) } ]' \
  | jq -c '.[]' | sort -R | head -n "$N" > /tmp/calib_sample.jsonl

if [ ! -s /tmp/calib_sample.jsonl ]; then
  echo "calibrate.sh: no pairwise judgments matched (filter '$FILTER') — nothing sampled, leaving existing $KEY/$SHEET untouched." >&2
  rm -f /tmp/calib_sample.jsonl
  exit 1
fi

: > "$KEY"
{
  echo "# Calibration audit — pick the better answer (or tie). Length is not merit."
  echo
  i=0
  while IFS= read -r row; do
    i=$((i + 1))
    base=$(printf '%s' "$row" | jq -r '.base'); chall=$(printf '%s' "$row" | jq -r '.challenger')
    qid=$(printf '%s' "$row" | jq -r '.qid'); rep=$(printf '%s' "$row" | jq -r '.repeat')
    verdict=$(printf '%s' "$row" | jq -r '.verdict')
    # Opaque id: config names in the sheet would break blinding
    pair_id=$(printf 'cal-%02d' "$i")
    # Randomize which config is shown as A
    if [ $((RANDOM % 2)) -eq 0 ]; then a_is=base; a_cfg=$base; b_cfg=$chall; else a_is=challenger; a_cfg=$chall; b_cfg=$base; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pair_id" "$verdict" "$a_is" "$chall" "$qid" "$rep" >> "$KEY"
    echo "## Pair $i (id: $pair_id)"
    echo
    jq -r --arg id "$qid" 'select(.id == $id) | "**Q:** " + .q' questions.jsonl
    echo
    echo "**Answer A:**"
    echo
    jq -r '.answer' "results/raw/${a_cfg}__${qid}__r${rep}.json"
    echo
    echo "**Answer B:**"
    echo
    jq -r '.answer' "results/raw/${b_cfg}__${qid}__r${rep}.json"
    echo
    echo '---'
    echo
  done < /tmp/calib_sample.jsonl
} > "$SHEET"
rm -f /tmp/calib_sample.jsonl
echo "wrote $SHEET ($N blind pairs) and $KEY (do not peek)."
echo "record verdicts in results/calibration_human.tsv (pair_id<TAB>A|B|tie), then: calibrate.sh score"
