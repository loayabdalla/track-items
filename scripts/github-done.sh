#!/usr/bin/env bash
# Prints your GitHub work in a time window, as JSON, for the daily brief and the progress log.
# One GraphQL call: PRs of yours that merged, PRs you opened, and reviews you submitted.
# Usage: github-done.sh <since> [until]
#   since, until: ISO 8601 UTC, for example 2026-11-05T08:00:00Z. No until means "now".
set -euo pipefail

SINCE="${1:?Usage: github-done.sh <since ISO 8601 UTC time> [until ISO 8601 UTC time]}"
UNTIL="${2:-}"
DAY="${SINCE:0:10}"
RANGE=">=$DAY"
[[ -n "$UNTIL" ]] && RANGE="$DAY..${UNTIL:0:10}"

read -r -d '' QUERY <<'GRAPHQL' || true
query($merged: String!, $opened: String!, $reviewed: String!) {
  viewer { login }
  merged: search(query: $merged, type: ISSUE, first: 100) {
    nodes { ... on PullRequest { number title url mergedAt additions deletions repository { nameWithOwner } } }
  }
  opened: search(query: $opened, type: ISSUE, first: 50) {
    nodes { ... on PullRequest { number title url createdAt isDraft repository { nameWithOwner } } }
  }
  reviewed: search(query: $reviewed, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number title url
        author { login }
        repository { nameWithOwner }
        latestReviews(first: 50) { nodes { author { login } submittedAt state } }
      }
    }
  }
}
GRAPHQL

read -r -d '' JQ <<'JQ' || true
def loc: .repository.nameWithOwner + " #" + (.number | tostring);
.data as $d
| $d.viewer.login as $me
| "__SINCE__" as $since
| "__UNTIL__" as $until
| def inwin($t): ($t // "") >= $since and ($until == "" or ($t // "") < $until);
  {
    merged: [($d.merged.nodes // [])[] | select(.url != null and inwin(.mergedAt))
             | { title, url, where: loc, at: .mergedAt, additions, deletions }],
    opened: [($d.opened.nodes // [])[] | select(.url != null and inwin(.createdAt))
             | { title, url, where: loc, at: .createdAt, draft: .isDraft }],
    reviewed: [($d.reviewed.nodes // [])[] | select(.url != null)
               | . as $p
               | ([$p.latestReviews.nodes[]? | select(.author.login? == $me and inwin(.submittedAt))] | last) as $r
               | select($r != null)
               | { title: $p.title, url: $p.url, where: ($p | loc), author: ("@" + ($p.author.login // "ghost")), state: $r.state, at: $r.submittedAt }]
  }
JQ

JQ="${JQ//__SINCE__/$SINCE}"
JQ="${JQ//__UNTIL__/$UNTIL}"

gh api graphql \
  -f query="$QUERY" \
  -f merged="is:pr author:@me merged:$RANGE" \
  -f opened="is:pr author:@me created:$RANGE" \
  -f reviewed="is:pr reviewed-by:@me -author:@me updated:>=$DAY" \
  --jq "$JQ"
