#!/usr/bin/env bash
# Send one question to Gemini 4 Neon and print the answer and its cost.
#
# Why this exists: it is the opt-in "ask Gemini" path of the oracle skill.
# It uses the same Oracle system prompt as the Fable path, with Google Search
# in place of WebSearch.
#
# Usage:
#   gemini_oracle.sh <question-file> [--system-prompt-file <file>] [--json]
#
# Default output: the answer text, then one stats line, for example
#   [245 in / 77 out + 0 thinking tokens · $0.00126 + 2 searches (free in the first 5,000 per month, else $0.028)]
# With --json: one JSON object with the answer, the token counts and the cost.
# The eval harness in evals/ uses that form.
#
# The cost is token counts multiplied by the prices that gemini_price.sh reads
# from Google's pricing page. If gemini_price.sh fails, or if the response has
# token counts that this script does not know how to price, the stats line
# says "cost unknown" and keeps the token counts.
#
# Google Search is billed apart from tokens: a fee per search, after a free
# monthly allowance. No API says how much of the allowance is left, so the
# script cannot know if a search was billed. The stats line shows the search
# fee as its own amount, which is what the searches cost if the allowance is
# used up. If gemini_price.sh cannot read the fee, the line says "fee unknown".
#
# On an API error the script prints Google's error code and message to stderr
# and exits non-zero. There is no fallback to another model.

# -u: stop on a variable that was never set.
# -o pipefail: a pipeline fails when any command in it fails, not only the last one.
set -u -o pipefail

API_URL="https://generativelanguage.googleapis.com/v1beta/interactions"
API_REVISION="2026-05-20"
MODEL="gemini-4-neon"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

question_file=""
system_prompt_file="$SCRIPT_DIR/system_prompt.txt"
output_format="text"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      echo "usage: gemini_oracle.sh <question-file> [--system-prompt-file <file>] [--json]" >&2
      exit 0
      ;;
    --system-prompt-file)
      system_prompt_file="$2"
      shift 2
      ;;
    --json)
      output_format="json"
      shift
      ;;
    *)
      question_file="$1"
      shift
      ;;
  esac
done

# Print a reason to stderr and stop with a failure status.
fail() {
  echo "gemini_oracle.sh: $1" >&2
  exit 1
}

if [ -z "${GEMINI_API_KEY:-}" ]; then
  fail "GEMINI_API_KEY is not set. Export it in the shell profile, then try again."
fi
if ! [ -s "$question_file" ]; then
  fail "question file is missing or empty: $question_file"
fi
if ! [ -s "$system_prompt_file" ]; then
  fail "system prompt file is missing or empty: $system_prompt_file"
fi

request_file=$(mktemp)
response_file=$(mktemp)
# The trap deletes both temporary files when the script ends for any reason,
# an error or Ctrl-C included. The response file holds the full answer.
trap 'rm -f "$request_file" "$response_file"' EXIT

# Build the JSON request with jq, so quotes and newlines in the question are
# escaped correctly. --rawfile reads a whole file into a jq variable, so a
# long question never has to fit on a command line.
# "store: false" tells Google not to keep the interaction.
jq -n \
  --arg model "$MODEL" \
  --rawfile question "$question_file" \
  --rawfile system_prompt "$system_prompt_file" \
  '{model: $model, input: $question, system_instruction: $system_prompt,
    tools: [{type: "google_search"}], store: false}' \
  > "$request_file" \
  || fail "could not build the request JSON"

# The API key header is not written on curl's command line, because any user
# of the computer can read a command line with "ps". "--header @file" makes
# curl read the header from a file, and "<(...)" gives curl the output of
# printf as that file. printf is part of bash, so the key is in no command line.
# The response body goes to a file, so that curl prints only the HTTP status code.
http_status=$(
  curl --silent --show-error --max-time 300 \
    --output "$response_file" --write-out '%{http_code}' \
    --request POST "$API_URL" \
    --header @<(printf 'x-goog-api-key: %s\n' "$GEMINI_API_KEY") \
    --header "Content-Type: application/json" \
    --header "Api-Revision: $API_REVISION" \
    --data-binary "@$request_file"
)
curl_exit_code=$?

if [ "$curl_exit_code" -ne 0 ]; then
  fail "the request to Google failed (curl exit code $curl_exit_code)"
fi

if [ "$http_status" != "200" ]; then
  # Google's error body is {"error": {"code": "...", "message": "..."}}.
  # Some errors (a bad API key is one) come in an older shape: the object is
  # wrapped in a one-item array, "code" is the HTTP number, and the readable
  # code is in "status". The jq program accepts both shapes.
  # If the body is neither shape, show the start of the raw body instead.
  error_text=$(jq -r '
    (if type == "array" then .[0] else . end)
    | .error
    | "\(.status // .code): \(.message)"' "$response_file" 2>/dev/null)
  if [ -z "$error_text" ] || [ "$error_text" = "null: null" ]; then
    error_text=$(head -c 500 "$response_file")
  fi
  fail "Gemini API error (HTTP $http_status): $error_text"
fi

# The answer is the text of every "model_output" step, joined together.
answer=$(jq -r '[.steps[]? | select(.type == "model_output") | .content[]? | select(.type == "text") | .text] | join("\n")' "$response_file")
interaction_status=$(jq -r '.status // "missing"' "$response_file")

if [ -z "$answer" ]; then
  fail "Gemini returned no answer text (status: $interaction_status)"
fi

# Read the token counts. "// 0" gives 0 when a field is absent.
input_tokens=$(jq -r '.usage.total_input_tokens // 0' "$response_file")
output_tokens=$(jq -r '.usage.total_output_tokens // 0' "$response_file")
thought_tokens=$(jq -r '.usage.total_thought_tokens // 0' "$response_file")
cached_tokens=$(jq -r '.usage.total_cached_tokens // 0' "$response_file")
search_count=$(jq -r '[.usage.grounding_tool_count[]? | select(.type == "google_search") | .count] | add // 0' "$response_file")

# Decide if these counts can be priced. The cost formula below was checked
# against real responses in which:
#   total_tokens = total_input_tokens + total_output_tokens + total_thought_tokens
# and the cached tokens were a part of the input tokens. "jq -e" exits
# non-zero when the test is false. Then the cost stays unknown, for example
# when the usage object is absent, or when it reports tool-use tokens, which
# no checked response had and which this script does not know how to price.
usage_is_priceable="no"
if jq -e '
    .usage as $usage
    | ($usage.total_input_tokens | type) == "number"
    and ($usage.total_output_tokens | type) == "number"
    and ($usage.total_tool_use_tokens // 0) == 0
    and ($usage.total_cached_tokens // 0) <= $usage.total_input_tokens
    and $usage.total_tokens ==
        $usage.total_input_tokens + $usage.total_output_tokens + ($usage.total_thought_tokens // 0)
  ' "$response_file" > /dev/null 2>&1; then
  usage_is_priceable="yes"
fi

# Cost. Cached tokens are a part of the input tokens, and Google bills them
# at the lower caching price. Thinking tokens are billed at the output price.
cost=""
if [ "$usage_is_priceable" = "yes" ] && prices=$("$SCRIPT_DIR/gemini_price.sh"); then
  # "read" splits the one line of three prices into three variables.
  read -r input_price output_price cached_price <<< "$prices"
  cost=$(awk \
    -v input_tokens="$input_tokens" -v output_tokens="$output_tokens" \
    -v thought_tokens="$thought_tokens" -v cached_tokens="$cached_tokens" \
    -v input_price="$input_price" -v output_price="$output_price" \
    -v cached_price="$cached_price" '
    BEGIN {
      fresh_input_tokens = input_tokens - cached_tokens
      dollars = fresh_input_tokens * input_price
      dollars = dollars + cached_tokens * cached_price
      dollars = dollars + (output_tokens + thought_tokens) * output_price
      dollars = dollars / 1000000
      # %.6f rounds to a millionth of a dollar and never uses the "1.2e-05"
      # form. The two sub() calls then remove the zeros at the end, and a
      # decimal point that has nothing after it: 0.012600 becomes 0.0126.
      text = sprintf("%.6f", dollars)
      sub(/0+$/, "", text)
      sub(/\.$/, "", text)
      print text
    }')
fi

# Search fee: what the searches of this call cost if the free monthly
# allowance is already used up. It stays empty when it cannot be read.
search_fee=""
free_searches_per_month=""
if [ "$search_count" -gt 0 ] && fee_line=$("$SCRIPT_DIR/gemini_price.sh" --search-fee); then
  read -r dollars_per_thousand_searches free_searches_per_month <<< "$fee_line"
  search_fee=$(awk \
    -v search_count="$search_count" \
    -v dollars_per_thousand_searches="$dollars_per_thousand_searches" '
    BEGIN {
      text = sprintf("%.6f", search_count * dollars_per_thousand_searches / 1000)
      sub(/0+$/, "", text)
      sub(/\.$/, "", text)
      print text
    }')
fi

if [ "$output_format" = "json" ]; then
  # --argjson needs a JSON value, so an unknown cost becomes null.
  cost_json="null"
  if [ -n "$cost" ]; then
    cost_json="$cost"
  fi
  # 0 when the call made no searches, null when the fee cannot be read.
  search_fee_json="null"
  if [ "$search_count" -eq 0 ]; then
    search_fee_json="0"
  elif [ -n "$search_fee" ]; then
    search_fee_json="$search_fee"
  fi
  jq -n -c \
    --arg answer "$answer" --arg status "$interaction_status" \
    --argjson input_tokens "$input_tokens" --argjson output_tokens "$output_tokens" \
    --argjson thought_tokens "$thought_tokens" --argjson cached_tokens "$cached_tokens" \
    --argjson search_count "$search_count" --argjson cost "$cost_json" \
    --argjson search_fee "$search_fee_json" \
    '{answer: $answer, status: $status,
      usage: {input_tokens: $input_tokens, output_tokens: $output_tokens,
              thought_tokens: $thought_tokens, cached_tokens: $cached_tokens},
      search_count: $search_count, total_cost_usd: $cost,
      search_fee_usd_if_billed: $search_fee}'
  exit 0
fi

# printf, not echo: echo would treat an answer that starts with "-n" as an option.
printf '%s\n' "$answer"
if [ "$interaction_status" != "completed" ]; then
  echo "(Gemini status: $interaction_status. The answer can be incomplete.)"
fi

stats="$input_tokens in / $output_tokens out + $thought_tokens thinking tokens"
if [ -n "$cost" ]; then
  stats="$stats · \$$cost"
else
  stats="$stats · cost unknown"
fi
if [ "$search_count" -gt 0 ]; then
  if [ -n "$search_fee" ]; then
    stats="$stats + $search_count searches (free in the first $free_searches_per_month per month, else \$$search_fee)"
  else
    stats="$stats + $search_count searches (fee unknown)"
  fi
fi
echo "[$stats]"
