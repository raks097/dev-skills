#!/usr/bin/env bash
# Re-trigger a fresh Greptile review by closing and reopening the PR.
# This is the dependable re-trigger — a plain push often does not re-run Greptile.
# Comment history is preserved across close/reopen.
#
# Usage: retrigger.sh <pr>            (uses the current repo)
#    or: retrigger.sh <pr> <owner/repo>
set -euo pipefail

PR=${1:?pr}
REPO_ARG=()
[ -n "${2:-}" ] && REPO_ARG=(--repo "$2")

gh pr close "$PR" "${REPO_ARG[@]}"
sleep 2
gh pr reopen "$PR" "${REPO_ARG[@]}"
echo "re-triggered #$PR — poll for the new score (scripts/poll-score.sh)"
