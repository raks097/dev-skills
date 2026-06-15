#!/usr/bin/env bash
# Block until the webhook receiver records a Greptile re-review of a PR at a
# specific head commit, then print the score. This is the event-driven
# counterpart to poll-score.sh — it tails the events file the receiver writes
# instead of hitting the API on a timer.
#
# Usage: await-review.sh <pr> <head_sha> [events_file] [timeout_secs]
#   defaults: events_file=$GREPTILE_EVENTS or /tmp/greptile-events.jsonl
#             timeout_secs=1800
#
# Exit 0 with the score on a match; exit 0 with "timeout" if none arrives in time.
set -euo pipefail

PR=${1:?pr}; HEAD=${2:?head_sha}
EVENTS=${3:-${GREPTILE_EVENTS:-/tmp/greptile-events.jsonl}}
TIMEOUT=${4:-1800}
SHORT=${HEAD:0:8}

[ -f "$EVENTS" ] || : > "$EVENTS"
echo "awaiting review of PR#$PR @ $SHORT (events: $EVENTS, timeout ${TIMEOUT}s)"

# Follow new lines; a review event for our PR whose commit matches HEAD is the signal.
# (A summary issue_comment carries the score but no commit; we accept it as a fallback
# once we've also seen any review for this PR, so the score is the freshly-posted one.)
deadline=$(( $(date +%s) + TIMEOUT ))
tail -n +1 -f "$EVENTS" | while IFS= read -r line; do
  [ "$(date +%s)" -ge "$deadline" ] && { echo "timeout"; exit 0; }
  pr=$(printf '%s' "$line" | sed -n 's/.*"pr":\([0-9]*\).*/\1/p')
  [ "$pr" = "$PR" ] || continue
  commit=$(printf '%s' "$line" | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p')
  score=$(printf '%s' "$line" | sed -n 's/.*"score":"\([0-9]\/5\)".*/\1/p')
  [ -n "$commit" ] || continue
  # match if either SHA is a prefix of the other (GitHub sends the full 40-char id)
  case "$HEAD" in "$commit"*) : ;; *) case "$commit" in "$HEAD"*) : ;; *) continue ;; esac ;; esac
  echo "review landed for $SHORT: score=${score:-unknown}"; exit 0
done
