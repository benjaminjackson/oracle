#!/usr/bin/env bash
# Judge generated answers. Two modes:
#   judge.sh pairwise --base <cfg> --challenger <cfg> [--ids file] [--repeats N] [--parallel N]
#       Each (question, repeat) pair judged twice, position-swapped (o1: A=base, o2: A=challenger).
#       Orientation disagreement is scored as a tie by summary.sh.
#   judge.sh anchor [--configs id1,id2] [--repeats N] [--parallel N]
#       Absolute grading of anchor questions against recorded truth.
# Resume-safe: existing judgment files are skipped.
set -u
cd "$(dirname "$0")"

MODE="${1:-}"; shift || true
BASE="" CHALL="" ONLY="" IDS="" REPEATS=1 PAR=4
while [ $# -gt 0 ]; do
  case "$1" in
    --base)       BASE="$2";    shift 2 ;;
    --challenger) CHALL="$2";   shift 2 ;;
    --configs)    ONLY="$2";    shift 2 ;;
    --ids)        IDS="$2";     shift 2 ;;
    --repeats)    REPEATS="$2"; shift 2 ;;
    --parallel)   PAR="$2";     shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

mkdir -p results/judgments
tasks=$(mktemp)

case "$MODE" in
  pairwise)
    [ -n "$BASE" ] && [ -n "$CHALL" ] || { echo "pairwise needs --base and --challenger" >&2; exit 1; }
    for qid in $(jq -r '.id' questions.jsonl); do
      if [ -n "$IDS" ] && ! grep -qx "$qid" "$IDS"; then continue; fi
      r=1
      while [ "$r" -le "$REPEATS" ]; do
        if [ -s "results/raw/${BASE}__${qid}__r${r}.json" ] && [ -s "results/raw/${CHALL}__${qid}__r${r}.json" ]; then
          for o in 1 2; do
            [ -s "results/judgments/pw__${BASE}__vs__${CHALL}__${qid}__r${r}__o${o}.json" ] || \
              echo "pw $BASE $CHALL $qid $r $o"
          done
        fi
        r=$((r + 1))
      done
    done > "$tasks"
    N_ARGS=6
    ;;
  anchor)
    for cfg in $(jq -r '.id' configs.jsonl); do
      if [ -n "$ONLY" ]; then case ",$ONLY," in *",$cfg,"*) ;; *) continue ;; esac; fi
      for qid in $(jq -r 'select(.anchor).id' questions.jsonl); do
        r=1
        while [ "$r" -le "$REPEATS" ]; do
          if [ -s "results/raw/${cfg}__${qid}__r${r}.json" ]; then
            [ -s "results/judgments/anch__${cfg}__${qid}__r${r}.json" ] || echo "anchor $cfg $qid $r"
          fi
          r=$((r + 1))
        done
      done
    done > "$tasks"
    N_ARGS=4
    ;;
  *) echo "usage: judge.sh pairwise|anchor ..." >&2; exit 1 ;;
esac

n=$(wc -l < "$tasks" | tr -d ' ')
echo "judge.sh $MODE: $n judgments to make (parallel=$PAR)" >&2
[ "$n" -eq 0 ] && { rm -f "$tasks"; exit 0; }
xargs -P "$PAR" -n "$N_ARGS" ./judge_one.sh < "$tasks"
rm -f "$tasks"
echo "judge.sh: done. Rerun to retry any FAIL lines." >&2
