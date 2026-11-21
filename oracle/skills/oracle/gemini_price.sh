#!/usr/bin/env bash
# Print today's Gemini 4 Neon prices, read from Google's pricing page.
#
# Why this exists: no Gemini API response has a cost field, so the oracle skill
# must multiply token counts by a price. The price changes on known dates, so
# it is read from the pricing page each time and is never hard-coded.
#
# Output on success, one line, US dollars per 1 million tokens:
#   <input price> <output price> <cached input price>
#
# The script fails closed. If any step does not find exactly what it expects,
# it prints a reason to stderr and exits non-zero. The caller then shows
# "cost unknown". It never guesses a price.
#
# With --search-fee the output is the Google Search fee instead, one line:
#   <US dollars per 1,000 searches> <free searches per month>
# Google bills searches per search, not per token, and only after the free
# monthly allowance is used. No API reports how much of the allowance is left.
#
# Usage:
#   gemini_price.sh                      download (or reuse) the cached page
#   gemini_price.sh --search-fee         print the search fee, not the token prices
#   gemini_price.sh --file <path>        parse this file, no download (for tests)
#   gemini_price.sh --today <YYYYMMDD>   use this date as today (for tests)
set -u

PRICING_URL="https://aistudio.google.com/docs/pricing.md"
CACHE_FILE="$HOME/.cache/oracle/gemini-pricing.md"
MODEL_HEADING='## Gemini 4 Neon  {% id="gemini-4-neon" %}'
PAID_COLUMN_TITLE="Paid Tier, per 1M tokens in USD"
ALLOWED_NOTE="Implicit caching only (explicit caching is not supported)."

SEARCH_ROW_LABEL='Grounding with Google Search{% sup %}*{% /sup %}'

pricing_file=""
today=""
wanted="token-prices"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      echo "usage: gemini_price.sh [--search-fee] [--file <pricing.md>] [--today <YYYYMMDD>]" >&2
      exit 0
      ;;
    --search-fee)
      wanted="search-fee"
      shift
      ;;
    --file)
      pricing_file="$2"
      shift 2
      ;;
    --today)
      today="$2"
      shift 2
      ;;
    *)
      echo "gemini_price.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# Print a reason to stderr and stop with a failure status.
fail() {
  echo "gemini_price.sh: $1" >&2
  exit 1
}

# Download the pricing page into the cache when the cached copy is missing or
# more than 24 hours old. The page sends no ETag and no Last-Modified header,
# so the age of the cached file is the only way to decide.
refresh_cache() {
  local cache_is_fresh="no"
  if [ -s "$CACHE_FILE" ]; then
    # "find -mmin +1440" prints the file only when it was last modified more
    # than 1440 minutes (24 hours) ago. No output means the file is fresh.
    local stale_listing
    stale_listing=$(find "$CACHE_FILE" -mmin +1440)
    if [ -z "$stale_listing" ]; then
      cache_is_fresh="yes"
    fi
  fi
  if [ "$cache_is_fresh" = "yes" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$CACHE_FILE")" || fail "cannot create the cache directory"
  # mktemp gives each run its own download file, so two runs at the same time
  # cannot write over each other. The trap deletes the file when the script
  # ends for any reason. After the "mv" below the file is gone, and "rm -f"
  # on a missing file does nothing.
  download_file=$(mktemp "$CACHE_FILE.XXXXXX") || fail "cannot create a download file"
  trap 'rm -f "$download_file"' EXIT
  # --fail makes curl exit non-zero on an HTTP error instead of saving the error page.
  if ! curl --silent --show-error --location --fail --max-time 20 \
      --user-agent "Mozilla/5.0" --output "$download_file" "$PRICING_URL"; then
    fail "could not download $PRICING_URL"
  fi
  # Keep the download only if it looks like the pricing page. A truncated or
  # wrong page must not replace the cache.
  if ! grep --quiet --fixed-strings --line-regexp "$MODEL_HEADING" "$download_file"; then
    fail "the downloaded page has no Gemini 4 Neon heading"
  fi
  mv "$download_file" "$CACHE_FILE" || fail "cannot write $CACHE_FILE"
}

# Print the "Standard" tab of the Gemini 4 Neon section of the pricing page.
# Fails unless there is exactly one such heading and exactly one such tab.
# The Batch, Flex and Priority tabs have other prices, so they must be left out.
standard_tab_of_model_section() {
  awk -v heading="$MODEL_HEADING" '
    # A line that starts with "## " opens a new model section.
    /^## / {
      if ($0 == heading) {
        heading_count = heading_count + 1
        in_section = 1
      } else {
        in_section = 0
      }
      in_standard_tab = 0
      next
    }
    in_section && /\{% tab title="Standard" %\}/ {
      standard_tab_count = standard_tab_count + 1
      in_standard_tab = 1
      next
    }
    in_section && /\{% \/tab %\}/ {
      in_standard_tab = 0
      next
    }
    in_standard_tab {
      print
    }
    END {
      if (heading_count != 1 || standard_tab_count != 1) {
        exit 1
      }
    }
  ' "$1"
}

# Print the third cell (the paid tier column) of the one table row whose first
# cell is exactly the given label. Reads the Standard tab text on stdin.
#
# The page is Markdoc. A table row is a list of cells that each start with
# "* ". A cell can continue on the next lines. A line with only "---" ends
# the row.
paid_cell_of_row() {
  awk -v wanted_label="$1" '
    # Remove spaces at both ends and join repeated spaces into one.
    function tidy(text) {
      gsub(/[ \t]+/, " ", text)
      sub(/^ /, "", text)
      sub(/ $/, "", text)
      return text
    }
    # Called at the end of each row: keep the paid cell if the label matches.
    function finish_row() {
      if (cell_count == 3 && tidy(cell[1]) == wanted_label) {
        match_count = match_count + 1
        paid_cell = tidy(cell[3])
      }
      cell_count = 0
    }
    {
      line = tidy($0)
    }
    line == "---" || line ~ /^\{% \/table %\}/ {
      finish_row()
      next
    }
    line ~ /^\* / {
      cell_count = cell_count + 1
      cell[cell_count] = substr(line, 3)
      next
    }
    cell_count > 0 {
      cell[cell_count] = cell[cell_count] " " line
    }
    END {
      finish_row()
      if (match_count != 1) {
        exit 1
      }
      print paid_cell
    }
  '
}

# Convert a date such as "November 30, 2026" (given as three arguments: month
# name, day, year) to the number 20261130, so two dates compare as integers.
date_to_number() {
  local month_name="$1"
  local day="$2"
  local year="$3"
  local month_number
  case "$month_name" in
    January)   month_number=1 ;;
    February)  month_number=2 ;;
    March)     month_number=3 ;;
    April)     month_number=4 ;;
    May)       month_number=5 ;;
    June)      month_number=6 ;;
    July)      month_number=7 ;;
    August)    month_number=8 ;;
    September) month_number=9 ;;
    October)   month_number=10 ;;
    November)  month_number=11 ;;
    December)  month_number=12 ;;
    *) return 1 ;;
  esac
  # The day comes from a pattern that allows any digits. Allow only 1 or 2
  # digits here, and then only the values 1 to 31.
  local one_or_two_digits='^[0-9]{1,2}$'
  if ! [[ "$day" =~ $one_or_two_digits ]]; then
    return 1
  fi
  if [ "$((10#$day))" -lt 1 ] || [ "$((10#$day))" -gt 31 ]; then
    return 1
  fi
  # "10#" makes bash read "08" and "09" as decimal numbers, not as bad octal.
  printf '%04d%02d%02d\n' "$((10#$year))" "$month_number" "$((10#$day))"
}

# Print the price in a paid-tier cell that applies today. Two cell shapes are
# accepted, and anything else fails:
#   "$4.00"
#   "$2.00 through November 30, 2026. $4.00 starting December 1, 2026."
# After the price, the cell must be empty or must be exactly the one note in
# ALLOWED_NOTE. Any other text fails, because it can change what the price
# means: for example a second price that depends on the prompt size, or
# "until the promotion ends".
price_for_today() {
  local cell_text="$1"
  # The patterns are kept in variables because bash matches a quoted pattern
  # after "=~" as plain text, not as a regular expression.
  local dated_pattern='^\$([0-9]+\.[0-9]+) through ([A-Z][a-z]+) ([0-9]+), ([0-9]{4})\. \$([0-9]+\.[0-9]+) starting ([A-Z][a-z]+) ([0-9]+), ([0-9]{4})\.(.*)$'
  local plain_pattern='^\$([0-9]+\.[0-9]+)(.*)$'
  local price=""
  local note=""

  # After a successful "=~" match, bash puts each parenthesised group into
  # the BASH_REMATCH array, starting at index 1.
  if [[ "$cell_text" =~ $dated_pattern ]]; then
    local first_price="${BASH_REMATCH[1]}"
    local second_price="${BASH_REMATCH[5]}"
    note="${BASH_REMATCH[9]}"
    local last_day_of_first_price
    local first_day_of_second_price
    last_day_of_first_price=$(date_to_number "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}") || return 1
    first_day_of_second_price=$(date_to_number "${BASH_REMATCH[6]}" "${BASH_REMATCH[7]}" "${BASH_REMATCH[8]}") || return 1
    if [ "$last_day_of_first_price" -ge "$first_day_of_second_price" ]; then
      return 1
    fi
    if [ "$today" -le "$last_day_of_first_price" ]; then
      price="$first_price"
    elif [ "$today" -ge "$first_day_of_second_price" ]; then
      price="$second_price"
    else
      # Today is in a gap between the two date ranges.
      return 1
    fi
  elif [[ "$cell_text" =~ $plain_pattern ]]; then
    price="${BASH_REMATCH[1]}"
    note="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  if [ -n "$note" ] && [ "$note" != " $ALLOWED_NOTE" ]; then
    return 1
  fi
  echo "$price"
}

# Print the Google Search fee as "<dollars per 1,000 searches> <free searches
# per month>", or fail. The whole cell must match one known sentence, so a
# change in how Google words or structures the fee is never read as a price.
search_fee() {
  local cell_text
  cell_text=$(printf '%s\n' "$standard_tab" | paid_cell_of_row "$SEARCH_ROW_LABEL") \
    || fail "expected exactly one Google Search row with three cells"
  # The backslashes make ( ) [ ] $ and . match as plain characters.
  # "[^)]*" matches the link address, which is any text up to the next ")".
  local search_pattern='^([0-9,]+) free search requests per month \(shared across all Gemini 3 and newer models\), then \$([0-9]+(\.[0-9]+)?) per 1,000 requests \(subject to a \[daily cap\]\([^)]*\) of [0-9,]+ requests per day\)\.$'
  if ! [[ "$cell_text" =~ $search_pattern ]]; then
    fail "cannot read the Google Search fee from the cell: $cell_text"
  fi
  local free_searches_per_month="${BASH_REMATCH[1]}"
  local dollars_per_thousand="${BASH_REMATCH[2]}"
  # "${name//,/}" removes every comma, so "5,000" becomes "5000".
  echo "$dollars_per_thousand ${free_searches_per_month//,/}"
}

# Print today's price for the table row with the given label, or fail.
price_of_row() {
  local row_label="$1"
  local cell_text
  cell_text=$(printf '%s\n' "$standard_tab" | paid_cell_of_row "$row_label") \
    || fail "expected exactly one \"$row_label\" row with three cells"
  price_for_today "$cell_text" \
    || fail "cannot read a price for today from the \"$row_label\" cell: $cell_text"
}

if [ -z "$today" ]; then
  # Google is in California, so the dates on its pricing page are read as Pacific time.
  today=$(TZ=America/Los_Angeles date +%Y%m%d)
fi
valid_date_pattern='^[0-9]{8}$'
if ! [[ "$today" =~ $valid_date_pattern ]]; then
  fail "--today must be YYYYMMDD"
fi

if [ -z "$pricing_file" ]; then
  refresh_cache
  pricing_file="$CACHE_FILE"
fi
if ! [ -s "$pricing_file" ]; then
  fail "pricing file is missing or empty: $pricing_file"
fi

standard_tab=$(standard_tab_of_model_section "$pricing_file") \
  || fail "expected exactly one Gemini 4 Neon section with one Standard tab"

# Make sure the third column is still the paid tier, priced per 1M tokens.
paid_column_title=$(printf '%s\n' "$standard_tab" | paid_cell_of_row "Feature") \
  || fail "expected exactly one table header row"
if [ "$paid_column_title" != "$PAID_COLUMN_TITLE" ]; then
  fail "unexpected paid column title: $paid_column_title"
fi

if [ "$wanted" = "search-fee" ]; then
  search_fee
  exit $?
fi

# price_of_row calls "fail" inside $(...), which only ends that subshell.
# The "|| exit 1" ends the script itself.
input_price=$(price_of_row "Input price") || exit 1
output_price=$(price_of_row "Output price (including thinking tokens)") || exit 1
cached_price=$(price_of_row "Context caching price") || exit 1

echo "$input_price $output_price $cached_price"
