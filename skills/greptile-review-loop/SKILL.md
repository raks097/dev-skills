---
name: greptile-review-loop
description: Drive a GitHub pull request (or a stacked PR series) through Greptile bot reviews to a clean 5/5 confidence score. Use when a PR has a Greptile review with findings to address, when iterating a PR or stack toward a clean review, or when asked to "get the PR to 5/5", "address the greptile comments", "resolve the greptile conversations", or "loop the greptile review". Covers reading findings, fixing them, replying to and resolving each review thread, and re-triggering a fresh review via close/reopen — plus the stacked-PR mechanics for keeping each PR's fixes with its own code.
license: MIT
metadata:
  category: code-review
  tools: gh, git, greptile
allowed-tools: Bash Read Edit
---

# Greptile review loop

Greptile (`greptile-apps[bot]`) posts an automated review on each PR: one **summary
issue comment** containing `Confidence Score: N/5` plus a prioritised list of
findings, and **inline review threads** (badged P1/P2/P3) on specific lines. This
skill drives a PR — or a whole stacked series — to **5/5 with every conversation
resolved**, the bar maintainers ask for before merge.

## The loop (one PR at a time; in a stack, bottom-up)

```
read review → fix findings → reply+resolve each thread → close/reopen → poll score → repeat until 5/5
```

1. **Read the review** — summary score, inline findings, and thread IDs:
   ```bash
   OWNER=your-org REPO=your-repo PR=123   # set these for your PR
   # summary + score
   gh api repos/$OWNER/$REPO/issues/$PR/comments \
     --jq '[.[]|select(.user.login=="greptile-apps[bot]")]|last|.body' \
     | sed 's/<[^>]*>//g' | grep -iE "Confidence Score|safe to merge|once|if "
   # inline findings (path:line + text)
   gh api repos/$OWNER/$REPO/pulls/$PR/comments \
     --jq '.[]|"[\(.path):\(.line // .original_line)] \(.body|gsub("<[^>]*>";""))"'
   ```
   For thread IDs + resolution state, use the GraphQL `reviewThreads` query in
   `references/greptile-api.md`.

2. **Fix each finding** on the PR's branch. Fix the *real* defect, not the
   symptom — Greptile findings are usually correct (the recurring class is a
   guard/comment applied in two of three parallel spots; close the third).
   A finding phrased "Safe to merge **if** this is intentional" is a design
   question — it will **not** clear by asserting intent in a reply; either
   materially address it or accept the lower score.

3. **Reply to and resolve each thread** — comment the fix (cite the commit),
   then resolve the conversation. Replying is a REST call; resolving is GraphQL:
   ```bash
   CID=<first comment databaseId in the thread>   # from the pulls/.../comments list
   TID=<thread node id>                            # from the reviewThreads query
   gh api -X POST repos/$OWNER/$REPO/pulls/$PR/comments/$CID/replies \
     -f body="Fixed in <sha>: <one-line how>."
   gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:"'$TID'"}){thread{isResolved}} }'
   ```
   Force-pushing the branch auto-marks threads *outdated* (often *resolved*);
   still post the reply so the conversation closes with context. See
   `scripts/resolve-thread.sh`.

4. **Re-trigger the review** by close + reopen — this is the reliable signal:
   ```bash
   gh pr close $PR && sleep 2 && gh pr reopen $PR
   ```
   A plain push / synchronize frequently does **not** re-run Greptile; reopen
   does. Comment history survives close/reopen and force-push.

5. **Poll for the new score.** Greptile **edits its summary comment in place** —
   same `created_at`, new `updated_at`. Polling for a *new* comment will miss it;
   key on `updated_at` (or the score text). See `scripts/poll-score.sh`:
   ```bash
   ./scripts/poll-score.sh $OWNER $REPO $PR     # waits, then prints the new score
   ```

6. **Done when** `Confidence Score: 5/5` **and** zero unresolved threads:
   ```bash
   gh api graphql -f query='{repository(owner:"'$OWNER'",name:"'$REPO'"){pullRequest(number:'$PR'){reviewThreads(first:50){nodes{isResolved}}}}}' \
     --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length'
   ```
   Expect several iterations: fixing one finding often surfaces the next.

## Gotchas (the ones that cost time)

- **Re-trigger = close/reopen**, not push. Build this into the loop.
- **Score is edited in place** — poll `updated_at`/score text, not new comments.
- **Outdated ≠ replied.** Force-push resolves threads automatically; reply anyway
  so reviewers see *why* it's resolved.
- **One finding at a time.** Greptile tends to surface the next issue after you
  fix the current one — budget for 3–5 rounds on a substantive PR.
- **Design-judgment findings** ("…if intentional") need a material change, not a
  comment. Restoring a dropped capability beats arguing it was deliberate.
- **Keep fixes with their code.** In a stack, a fix for the bottom PR's code must
  live in the bottom PR — not stranded in a later one. If it is, restructure
  (see `references/stacked-prs.md`); otherwise Greptile flags the bottom PR for a
  defect whose fix it can't see.

## Stacked PR series

When the work is a commit series split into stacked PRs (each based on the
previous), the loop runs **bottom-up**, and the branches need maintenance as the
base PRs merge. The full playbook — decomposing the series, restructuring so each
PR is self-contained, and retargeting vs rebasing after a MERGE vs a SQUASH —
is in `references/stacked-prs.md`.

## References & scripts
- `references/greptile-api.md` — every `gh`/GraphQL command (reviews, threads,
  reply, resolve, poll), copy-paste ready.
- `references/stacked-prs.md` — building and maintaining a stacked PR series.
- `scripts/poll-score.sh` — wait for and print a PR's new Greptile score.
- `scripts/resolve-thread.sh` — reply to and resolve one review thread.
- `scripts/retrigger.sh` — close + reopen a PR to re-run the review.
