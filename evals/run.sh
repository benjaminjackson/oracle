#!/usr/bin/env bash
# Generate answers: configs x questions x repeats -> results/raw/<config>__<qid>__r<rep>.json
# Resume-safe: a non-empty output file means done; rerun to fill gaps.
# Usage: run.sh [--configs id1,id2] [--ids file-of-question-ids] [--repeats N] [--parallel N]
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

ONLY="" IDS="" REPEATS=1 PAR=4
while [ $# -gt 0 ]; do
  case "$1" in
    --configs)  ONLY="$2";    shift 2 ;;
    --ids)      IDS="$2";     shift 2 ;;
    --repeats)  REPEATS="$2"; shift 2 ;;
    --parallel) PAR="$2";     shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

mkdir -p results/raw
tasks=$(mktemp)
for cfg in $(jq -r '.id' configs.jsonl); do
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in *",$cfg,"*) ;; *) continue ;; esac
  fi
  for qid in $(jq -r '.id' questions.jsonl); do
    if [ -n "$IDS" ] && ! grep -qx "$qid" "$IDS"; then continue; fi
    r=1
    while [ "$r" -le "$REPEATS" ]; do
      [ -s "results/raw/${cfg}__${qid}__r${r}.json" ] || echo "$cfg $qid $r"
      r=$((r + 1))
    done
  done
done > "$tasks"

n=$(wc -l < "$tasks" | tr -d ' ')
echo "run.sh: $n calls to make (parallel=$PAR)" >&2
[ "$n" -eq 0 ] && { rm -f "$tasks"; exit 0; }
xargs -P "$PAR" -n 3 "$SELF_DIR/run_one.sh" < "$tasks"
rm -f "$tasks"
echo "run.sh: done. failures (if any) listed above as FAIL lines; rerun to retry." >&2
