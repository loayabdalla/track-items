#!/usr/bin/env bash
# Prints your GitHub active items as a JSON array in the Active Items board format.
# One GraphQL call. It returns:
#   - reviews requested from you (and team requests, if you turn them on)
#   - open PRs that you reviewed before
#   - open PRs that you watch: they involve you and you are subscribed
#   - your own open PRs
# Needs: gh, logged in.
#
# Settings (environment variables):
#   TRACK_ITEMS_PR_DAYS        Your own open PRs updated in the last N days. Default: 30.
#   TRACK_ITEMS_REVIEWED_DAYS  Open PRs you reviewed, updated in the last N days. Default: 30.
#   TRACK_ITEMS_WATCH_DAYS     Open PRs you watch, updated in the last N days. Default: 14.
#   TRACK_ITEMS_TEAM_DAYS      Team review requests updated in the last N days.
#                              Default: 0 (off, because team requests are noisy).
set -euo pipefail

PR_DAYS="${TRACK_ITEMS_PR_DAYS:-30}"
REVIEWED_DAYS="${TRACK_ITEMS_REVIEWED_DAYS:-30}"
WATCH_DAYS="${TRACK_ITEMS_WATCH_DAYS:-14}"
TEAM_DAYS="${TRACK_ITEMS_TEAM_DAYS:-0}"

days_ago() { date -u -v-"$1"d +%Y-%m-%d 2>/dev/null || date -u -d "$1 days ago" +%Y-%m-%d; }

WITH_TEAM=false
TEAM_SINCE="$(days_ago 1)"
if [ "$TEAM_DAYS" -gt 0 ]; then
  WITH_TEAM=true
  TEAM_SINCE="$(days_ago "$TEAM_DAYS")"
fi
BASE="is:pr is:open archived:false"
MINE_Q="$BASE author:@me updated:>=$(days_ago "$PR_DAYS")"
TEAM_Q="$BASE review-requested:@me updated:>=$TEAM_SINCE"
REVIEWED_Q="$BASE reviewed-by:@me -author:@me updated:>=$(days_ago "$REVIEWED_DAYS")"
WATCH_Q="$BASE involves:@me -author:@me -reviewed-by:@me updated:>=$(days_ago "$WATCH_DAYS")"

read -r -d '' QUERY <<'GRAPHQL' || true
query($mineQ: String!, $teamQ: String!, $reviewedQ: String!, $watchQ: String!, $withTeam: Boolean!) {
  viewer { login }
  direct: search(query: "is:pr is:open archived:false user-review-requested:@me", type: ISSUE, first: 50) {
    nodes { ...RequestedPR }
  }
  team: search(query: $teamQ, type: ISSUE, first: 50) @include(if: $withTeam) {
    nodes { ...RequestedPR }
  }
  reviewed: search(query: $reviewedQ, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number title url createdAt updatedAt viewerSubscription
        author { login }
        repository { nameWithOwner }
        latestReviews(first: 50) { nodes { author { login } submittedAt state } }
        commits(last: 1) { nodes { commit { committedDate } } }
      }
    }
  }
  watching: search(query: $watchQ, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number title url createdAt viewerSubscription
        author { login }
        repository { nameWithOwner }
      }
    }
  }
  mine: search(query: $mineQ, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number title url isDraft createdAt reviewDecision
        repository { nameWithOwner }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
}
fragment RequestedPR on PullRequest {
  number title url isDraft createdAt
  author { login }
  repository { nameWithOwner }
  timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 10) {
    nodes { ... on ReviewRequestedEvent { createdAt requestedReviewer { ... on User { login } } } }
  }
}
GRAPHQL

read -r -d '' JQ <<'JQ' || true
def pid: "gh:" + (.repository.nameWithOwner | gsub("/"; ":")) + ":" + (.number | tostring);
def loc: .repository.nameWithOwner + " #" + (.number | tostring);
def base: { id: pid, source: "github", title: .title, url: .url, where: loc };
.data as $d
| $d.viewer.login as $me
| [($d.direct.nodes // [])[] | select(.url != null) | .url] as $direct

# Review requests: direct first, then team.
| [(($d.direct.nodes // []) + ($d.team.nodes // []))[] | select(.url != null)
   | . as $p
   | any($direct[]; . == $p.url) as $isDirect
   | base + {
       kind: "review",
       from: ("@" + ($p.author.login // "ghost")),
       state: (if $p.isDraft then "Draft" elif $isDirect then "" else "Team request" end),
       priority: (if $isDirect then "normal" else "low" end),
       since: (([$p.timelineItems.nodes[]? | select(.requestedReviewer.login? == $me) | .createdAt] | last)
               // ([$p.timelineItems.nodes[]?.createdAt] | last)
               // $p.createdAt)
     }] as $requested

# PRs you reviewed before. New commits after your last review raise them.
| [($d.reviewed.nodes // [])[] | select(.url != null and .viewerSubscription != "IGNORED")
   | . as $p
   | ([$p.latestReviews.nodes[]? | select(.author.login? == $me)] | last) as $r
   | ($r.submittedAt // "") as $rt
   | ($p.commits.nodes[0].commit.committedDate // "") as $lc
   | ($rt != "" and $lc > $rt) as $newCommits
   | base + {
       kind: "review",
       from: ("@" + ($p.author.login // "ghost")),
       state: (if $newCommits then "New commits since your review"
               elif $r.state == "APPROVED" then "You approved"
               elif $r.state == "CHANGES_REQUESTED" then "You requested changes"
               else "You reviewed" end),
       priority: (if $newCommits then "normal" else "low" end),
       since: (if $newCommits then $lc elif $rt != "" then $rt else $p.updatedAt end)
     }] as $reviewed

# PRs you watch: they involve you, and you are still subscribed.
| [($d.watching.nodes // [])[] | select(.url != null and .viewerSubscription == "SUBSCRIBED")
   | base + {
       kind: "review",
       from: ("@" + (.author.login // "ghost")),
       state: "Watching",
       priority: "low",
       since: .createdAt
     }] as $watching

# Your own open PRs.
| [($d.mine.nodes // [])[] | select(.url != null)
   | base + {
       kind: "pr",
       from: "",
       state: ((if .isDraft then "Draft"
                elif .reviewDecision == "APPROVED" then "Approved"
                elif .reviewDecision == "CHANGES_REQUESTED" then "Changes requested"
                elif .reviewDecision == "REVIEW_REQUIRED" then "Waiting for review"
                else "Open" end)
               + (if ((.commits.nodes[0].commit.statusCheckRollup.state // "") | test("FAILURE|ERROR"))
                  then " · checks failing" else "" end)),
       priority: (if .reviewDecision == "CHANGES_REQUESTED" then "high" else "normal" end),
       since: .createdAt
     }] as $mine

# One item per PR. A review request wins over "reviewed", and "reviewed" wins over "watching".
| (($requested + $reviewed + $watching) | group_by(.url) | map(.[0])) + $mine
JQ

gh api graphql \
  -f query="$QUERY" \
  -f mineQ="$MINE_Q" -f teamQ="$TEAM_Q" -f reviewedQ="$REVIEWED_Q" -f watchQ="$WATCH_Q" \
  -F withTeam="$WITH_TEAM" \
  --jq "$JQ"
