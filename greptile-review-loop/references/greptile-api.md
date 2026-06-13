# Greptile / GitHub API cheatsheet

Every command the loop needs, copy-paste ready. Set `OWNER`, `REPO`, `PR` first.
The Greptile bot author login is `greptile-apps[bot]`.

```bash
OWNER=astra-sh; REPO=qvr; PR=261
```

## 1. Read the review

**Summary comment + confidence score** (the summary is an *issue* comment):

```bash
gh api repos/$OWNER/$REPO/issues/$PR/comments \
  --jq '[.[]|select(.user.login=="greptile-apps[bot]")]|last|.body' \
  | sed 's/<[^>]*>//g' \
  | grep -iE "Confidence Score|safe to merge|merge once|if the"
```

**Inline findings** (review comments are *pulls* comments — note the different path):

```bash
gh api repos/$OWNER/$REPO/pulls/$PR/comments \
  --jq '.[]|select(.user.login=="greptile-apps[bot]")
        |"[\(.path):\(.line // .original_line)] \(.body|gsub("<[^>]*>";""))"'
```

**Threads with IDs + resolution state** (GraphQL — needed to resolve):

```bash
gh api graphql -f query='
{ repository(owner:"'$OWNER'",name:"'$REPO'"){ pullRequest(number:'$PR'){
  reviewThreads(first:50){ nodes{
    id isResolved isOutdated
    comments(first:1){ nodes{ databaseId author{login} path line originalLine body } }
}}}}}' --jq '.data.repository.pullRequest.reviewThreads.nodes[]
  | select(.comments.nodes[0].author.login=="greptile-apps")
  | {threadId:.id, resolved:.isResolved, outdated:.isOutdated,
     cid:.comments.nodes[0].databaseId,
     path:.comments.nodes[0].path,
     line:(.comments.nodes[0].line // .comments.nodes[0].originalLine)}'
```

- `threadId` (e.g. `PRRT_...`) → used to **resolve**.
- `cid` (the first comment's `databaseId`, an integer) → used to **reply**.

## 2. Reply to a thread

A reply is a REST POST to the *thread's first comment*:

```bash
gh api -X POST repos/$OWNER/$REPO/pulls/$PR/comments/$CID/replies \
  -f body="Fixed in <sha>: <one line>."
```

## 3. Resolve a thread

Resolution is GraphQL only (no REST equivalent):

```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input:{threadId:"'$TID'"}){ thread{ isResolved } }
}'
```

Count remaining unresolved Greptile threads (loop exit check):

```bash
gh api graphql -f query='{repository(owner:"'$OWNER'",name:"'$REPO'"){pullRequest(number:'$PR'){reviewThreads(first:50){nodes{isResolved}}}}}' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length'
```

## 4. Re-trigger a review

```bash
gh pr close $PR && sleep 2 && gh pr reopen $PR
```

Greptile re-reviews on **reopen**. A plain push/synchronize often does not
re-run it — close/reopen is the dependable trigger. (If your org configured
Greptile to also run on synchronize, pushing works too; close/reopen always does.)

## 5. Poll for the new score

Greptile **edits** its existing summary comment — `created_at` stays the same,
`updated_at` moves. So watch `updated_at` (or the score text), never a new
comment:

```bash
base=$(gh api repos/$OWNER/$REPO/issues/$PR/comments \
  --jq '[.[]|select(.user.login=="greptile-apps[bot]")|.updated_at]|max')
until cur=$(gh api repos/$OWNER/$REPO/issues/$PR/comments \
  --jq '[.[]|select(.user.login=="greptile-apps[bot]")|.updated_at]|max'); \
  [ -n "$cur" ] && [ "$cur" != "$base" ]; do sleep 15; done
gh api repos/$OWNER/$REPO/issues/$PR/comments \
  --jq '[.[]|select(.user.login=="greptile-apps[bot]")]|last|.body' \
  | sed 's/<[^>]*>//g' | grep -iE "Confidence Score"
```

A full review typically lands ~1–5 min after reopen; poll on a 15s cadence with
a ~10 min ceiling.

## Notes
- `--jq` runs jq server-side via gh; strip HTML in Greptile bodies with
  `sed 's/<[^>]*>//g'` or `gsub("<[^>]*>";"")`.
- The bot's *issue* comment is the summary; its *pull* comments are the inline
  findings — they live at different API paths.
- Authentication: `gh auth status`. Replying/resolving requires write access to
  the repo.
