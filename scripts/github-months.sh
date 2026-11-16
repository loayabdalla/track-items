#!/usr/bin/env bash
# Prints monthly GitHub counts as JSON rows, for the progress log chart.
# One GraphQL call that asks only for counts (issueCount), so it is light.
# Usage: github-months.sh <first month YYYY-MM> [last month YYYY-MM]
#   No last month means the current month.
# Output: [{"month":"2026-07","merged":N,"opened":N,"reviewed":N}, ...]
# "reviewed" counts PRs by other people that you reviewed, by the month the PR was opened.
set -euo pipefail

FIRST="${1:?Usage: github-months.sh <first month YYYY-MM> [last month YYYY-MM]}"
LAST="${2:-$(date +%Y-%m)}"

fields=""
m="$FIRST"
i=0
months=()
while [[ "$m" < "$LAST" || "$m" == "$LAST" ]]; do
  start="$m-01"
  end="$(date -j -v+1m -v-1d -f %Y-%m-%d "$start" +%Y-%m-%d)"
  range="$start..$end"
  fields+="
  m${i}merged: search(query: \"is:pr author:@me merged:$range\", type: ISSUE) { issueCount }
  m${i}opened: search(query: \"is:pr author:@me created:$range\", type: ISSUE) { issueCount }
  m${i}reviewed: search(query: \"is:pr reviewed-by:@me -author:@me created:$range\", type: ISSUE) { issueCount }"
  months+=("$m")
  m="$(date -j -v+1m -f %Y-%m-%d "$start" +%Y-%m)"
  i=$((i + 1))
  [[ $i -gt 24 ]] && break
done

list="$(printf '"%s",' "${months[@]}")"
gh api graphql -f query="query {$fields
}" --jq "[${list%,}] as \$months | .data as \$d
  | [range(0; \$months | length) as \$i
     | { month: \$months[\$i],
         merged: \$d[\"m\(\$i)merged\"].issueCount,
         opened: \$d[\"m\(\$i)opened\"].issueCount,
         reviewed: \$d[\"m\(\$i)reviewed\"].issueCount }]"
