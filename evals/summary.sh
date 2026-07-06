#!/usr/bin/env bash
# jq-only reporting over results/raw and results/judgments.
set -u

echo "== Generation stats per config =="
cat results/raw/*.json 2>/dev/null | jq -s -r '
  group_by(.config)[] |
  "\(.[0].config)\tn=\(length)\tmean_out=\((map(.usage.output_tokens) | add / length) | round)\tmean_chars=\((map(.answer | length) | add / length) | round)\tmulti_turn_calls=\(map(select(.num_turns > 1)) | length)\ttotal_cost=$\((map(.total_cost_usd) | add * 100 | round) / 100)"'

echo
echo "== Anchor accuracy per config =="
cat results/judgments/anch__*.json 2>/dev/null | jq -s -r '
  group_by(.config)[] |
  "\(.[0].config)\t\(map(select(.correct)) | length)/\(length) correct\(if any(.correct | not) then "   missed: " + (map(select(.correct | not).qid) | unique | join(",")) else "" end)"' \
  || echo "(no anchor judgments yet)"

echo
echo "== Pairwise: challenger vs base (both orientations combined; disagreement = tie) =="
ls results/judgments/pw__*.json > /dev/null 2>&1 || { echo "(no pairwise judgments yet)"; exit 0; }
tmp_raw=$(mktemp)
cat results/raw/*.json > "$tmp_raw"
cat results/judgments/pw__*.json | jq -s -r --slurpfile qs questions.jsonl --slurpfile raw "$tmp_raw" '
  ($qs | map({key: .id, value: .domain}) | from_entries) as $dom |
  ($raw | map({key: (.config + "|" + .qid + "|" + (.repeat | tostring)), value: (.answer | length)}) | from_entries) as $len |
  [ group_by([.base, .challenger, .qid, .repeat])[] |
    select(length == 2) |
    { base: .[0].base, challenger: .[0].challenger, qid: .[0].qid, repeat: .[0].repeat,
      winner: (if .[0].winner == .[1].winner then .[0].winner else "tie" end) } |
    . + { domain: $dom[.qid],
          base_len: $len[.base + "|" + .qid + "|" + (.repeat | tostring)],
          chall_len: $len[.challenger + "|" + .qid + "|" + (.repeat | tostring)] } ] |
  group_by([.base, .challenger])[] |
  . as $g |
  ($g | map(select(.winner == "challenger")) | length) as $w |
  ($g | map(select(.winner == "base")) | length) as $l |
  ($g | map(select(.winner == "tie")) | length) as $t |
  ($g | map(select(.winner != "tie"))) as $dec |
  ($dec | map(select((.winner == "challenger" and .chall_len > .base_len) or
                     (.winner == "base" and .base_len > .chall_len))) | length) as $longer_wins |
  "\($g[0].challenger) vs \($g[0].base)  (n=\($g | length) pairs)" +
  "\n  challenger W=\($w)  T=\($t)  L=\($l)   net_losses=\($l - $w)" +
  "\n  decisive: \($dec | length)  challenger loss share of decisive: \(if ($dec | length) > 0 then (($l * 100 / ($dec | length)) | round) else 0 end)%" +
  "\n  length-bias check: longer answer won \($longer_wins)/\($dec | length) decisive pairs" +
  "\n  per-domain net losses (base wins - challenger wins): " +
  ([$g | group_by(.domain)[] |
    "\(.[0].domain)=\((map(select(.winner == "base")) | length) - (map(select(.winner == "challenger")) | length))"]
   | join("  ")) + "\n"'
rm -f "$tmp_raw"
