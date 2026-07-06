#!/usr/bin/env bash
# Phase 0 — anatomy (~27 cheap Fable calls + 1 Sonnet call). Resume-safe.
#  a) ablations x3: decompose the per-call input-token overhead
#  b) cache probe: 3 identical calls at t=0 / +10s / +6min
#  c) default-effort identification: output-token distributions on reasoning probes
#  d) judge --json-schema shape check (Sonnet)
set -u
case "${1:-}" in
  -h|--help) echo "usage: phase0.sh   (no args; run from inside an experiment directory)" >&2; exit 0 ;;
esac
mkdir -p results/phase0

mode=--safe-mode
[ -n "${ANTHROPIC_API_KEY:-}" ] && mode=--bare
P0=$(jq -r 'select(.id == "p0-default").prompt' configs.jsonl)
QA="What is the capital of Australia?"

save_if_ok() { # $1=file; json on stdin
  local out; out=$(cat)
  if printf '%s' "$out" | jq -e '.result' > /dev/null 2>&1; then
    printf '%s' "$out" > "$1"; echo "ok   $1"
  else
    echo "FAIL $1" >&2
  fi
}

# --- a) ablations ---
for v in full omit-tools empty-tools no-sysprompt bare; do
  for r in 1 2 3; do
    f="results/phase0/abl__${v}__r${r}.json"
    [ -s "$f" ] && continue
    case "$v" in
      full)         printf '%s' "$QA" | claude -p $mode --model fable --output-format json --tools "WebSearch" --allowedTools "WebSearch" --system-prompt "$P0" 2>/dev/null | save_if_ok "$f" ;;
      omit-tools)   printf '%s' "$QA" | claude -p $mode --model fable --output-format json --system-prompt "$P0" 2>/dev/null | save_if_ok "$f" ;;
      empty-tools)  printf '%s' "$QA" | claude -p $mode --model fable --output-format json --tools "" --allowedTools "" --system-prompt "$P0" 2>/dev/null | save_if_ok "$f" ;;
      no-sysprompt) printf '%s' "$QA" | claude -p $mode --model fable --output-format json --tools "WebSearch" --allowedTools "WebSearch" 2>/dev/null | save_if_ok "$f" ;;
      bare)         printf '%s' "$QA" | claude -p $mode --model fable --output-format json 2>/dev/null | save_if_ok "$f" ;;
    esac
  done
done

# --- b) cache probe (t=0, +10s, +6min) ---
if [ ! -s results/phase0/cache__c3.json ]; then
  for c in c1 c2 c3; do
    f="results/phase0/cache__${c}.json"
    if [ ! -s "$f" ]; then
      printf '%s' "$QA" | claude -p $mode --model fable --output-format json --tools "WebSearch" --allowedTools "WebSearch" --system-prompt "$P0" 2>/dev/null | save_if_ok "$f"
    fi
    [ "$c" = "c1" ] && sleep 10
    [ "$c" = "c2" ] && sleep 360
  done
fi

# --- c) default-effort identification ---
E1="A SaaS has 2,000 customers paying \$80/mo, 2.5% monthly churn, and adds 120 new customers per month. Is the customer base growing or shrinking, and at what size does it plateau?"
E2="Three services call each other in a chain, each 99.5% available, behind a 99.9% load balancer. What end-to-end availability can we honestly promise, and which lever improves it most?"
for e in none low medium high; do
  for p in 1 2; do
    f="results/phase0/effort__${e}__p${p}.json"
    [ -s "$f" ] && continue
    q="$E1"; [ "$p" = "2" ] && q="$E2"
    eff=""; [ "$e" != "none" ] && eff="--effort $e"
    printf '%s' "$q" | claude -p $mode --model fable --output-format json $eff --tools "WebSearch" --allowedTools "WebSearch" --system-prompt "$P0" 2>/dev/null | save_if_ok "$f"
  done
done

# --- d) judge schema shape check ---
f="results/phase0/schema_check.json"
if [ ! -s "$f" ]; then
  printf 'QUESTION: What is 2+2? ANSWER A: 4. ANSWER B: 5. Which answer is correct?' | \
    claude -p $mode --model sonnet --output-format json --tools "" --allowedTools "" \
    --json-schema '{"type":"object","properties":{"reason":{"type":"string"},"winner":{"type":"string","enum":["A","B","tie"]}},"required":["reason","winner"]}' \
    2>/dev/null | save_if_ok "$f"
fi

# --- report ---
echo
echo "== Phase 0 report =="
echo "-- Ablation (mean of 3): total input tokens per variant --"
for v in full omit-tools empty-tools no-sysprompt bare; do
  cat results/phase0/abl__${v}__r*.json 2>/dev/null | jq -s -r --arg v "$v" \
    'select(length > 0) | "\($v)\tin=\((map(.usage.input_tokens + .usage.cache_creation_input_tokens + .usage.cache_read_input_tokens) | add / length) | round)\tout=\((map(.usage.output_tokens) | add / length) | round)"'
done
echo "-- Cache probe (identical calls at t=0/+10s/+6min) --"
for c in c1 c2 c3; do
  [ -s "results/phase0/cache__${c}.json" ] && jq -r --arg c "$c" \
    '"\($c)\tinput=\(.usage.input_tokens)\tcache_creation=\(.usage.cache_creation_input_tokens)\tcache_read=\(.usage.cache_read_input_tokens)"' \
    "results/phase0/cache__${c}.json"
done
echo "-- Effort probes: output tokens (probe1, probe2) --"
for e in none low medium high; do
  cat results/phase0/effort__${e}__p*.json 2>/dev/null | jq -s -r --arg e "$e" \
    'select(length > 0) | "\($e)\t\(map(.usage.output_tokens) | join(", "))"'
done
echo "-- Judge schema check: .result type and parsed winner --"
[ -s "$f" ] && jq -r '.result | "type=\(type)  winner=\(if type == "string" then (fromjson.winner) else .winner end)"' "$f"
