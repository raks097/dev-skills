#!/usr/bin/env bash
# Wait for Greptile to (re)post/edit its review summary, then print the new
# confidence score. Greptile EDITS its summary comment in place, so we key on the
# summary's updated_at moving — not on a new comment appearing.
#
# Usage: poll-score.sh <owner> <repo> <pr> [max_iters] [sleep_secs]
#   defaults: max_iters=45  sleep_secs=15   (~11 min ceiling)
set -euo pipefail

OWNER=${1:?owner}; REPO=${2:?repo}; PR=${3:?pr}
MAX=${4:-45}; NAP=${5:-15}
BOT='greptile-apps[bot]'

latest_updated() {
  gh api "repos/$OWNER/$REPO/issues/$PR/comments" \
    --jq '[.[]|select(.user.login=="'"$BOT"'")|.updated_at]|max' 2>/dev/null
}
score_line() {
  gh api "repos/$OWNER/$REPO/issues/$PR/comments" \
    --jq '[.[]|select(.user.login=="'"$BOT"'")]|last|.body' 2>/dev/null \
    | sed 's/<[^>]*>//g' | grep -iE "Confidence Score|safe to merge|merge once|if the" | head -3
}

base=$(latest_updated)
echo "baseline summary updated_at: ${base:-none}"

for ((i=1; i<=MAX; i++)); do
  sleep "$NAP"
  cur=$(latest_updated)
  if [ -n "$cur" ] && [ "$cur" != "$base" ]; then
    echo "=== new review (updated $cur, after ${i} checks) ==="
    score_line
    exit 0
  fi
done

echo "=== no update after $((MAX*NAP))s; current score ==="
score_line
exit 0
