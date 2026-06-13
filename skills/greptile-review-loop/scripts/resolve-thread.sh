#!/usr/bin/env bash
# Reply to a Greptile review thread (documenting the fix) and resolve it.
# Reply is REST; resolve is GraphQL.
#
# Usage: resolve-thread.sh <owner> <repo> <pr> <comment_id> <thread_id> <reply_text>
#   comment_id : the thread's first comment databaseId (integer)
#   thread_id  : the reviewThread node id (e.g. PRRT_...)
# Get both from the reviewThreads GraphQL query in references/greptile-api.md.
set -euo pipefail

OWNER=${1:?owner}; REPO=${2:?repo}; PR=${3:?pr}
CID=${4:?comment_id}; TID=${5:?thread_id}; BODY=${6:?reply_text}

gh api -X POST "repos/$OWNER/$REPO/pulls/$PR/comments/$CID/replies" -f body="$BODY" >/dev/null
echo "replied to comment $CID"

gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:"'"$TID"'"}){ thread{ isResolved } } }' \
  --jq '.data.resolveReviewThread.thread.isResolved' | xargs echo "resolved thread $TID ->"
