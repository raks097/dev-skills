# Stacked PR series — build & maintain

When a body of work is one clean commit series, ship it as a **stack** of small
PRs (each based on the previous) instead of one large PR. Each reviews in
isolation; the Greptile loop runs **bottom-up**.

## Decompose

Pick contiguous commit ranges so each PR is one coherent unit. Don't reorder
history to group non-adjacent commits unless you're prepared to rewrite it —
prefer contiguous groups. A trivial trailing commit (a version bump) can be its
own tiny PR or fold into the last feature PR.

```bash
# branch per cumulative range, then push each
git branch feat/part-1  <sha-end-of-part-1>     # base: main
git branch feat/part-2  <sha-end-of-part-2>     # base: feat/part-1
git branch feat/part-3  <sha-end-of-part-3>     # base: feat/part-2
for b in feat/part-1 feat/part-2 feat/part-3; do git push -u origin "$b"; done

# open each PR against the previous branch
gh pr create --base main         --head feat/part-1 --title "…" --body "…"
gh pr create --base feat/part-1  --head feat/part-2 --title "…" --body "…"
gh pr create --base feat/part-2  --head feat/part-3 --title "…" --body "…"
```

Verify each PR's diff is scoped to its own commits (the stacked base does this):

```bash
gh pr diff <N> --name-only | wc -l
```

## Keep fixes with their code (the #1 stacked-PR mistake)

If you commit a fix *after* later commits, that fix lands in a **later** PR even
though it fixes an **earlier** PR's code. Greptile then flags the earlier PR for a
defect whose fix it can't see. Restructure so the fix sits in the PR it belongs
to:

```bash
# move an obs-fix commit down into the obs branch, then rebuild the upper branches
git checkout feat/part-1 && git cherry-pick <fix-sha>          # fix now in part-1
git checkout feat/part-2 && git reset --hard feat/part-1 \
  && git cherry-pick <part-2 commits…>                          # rebuild on new part-1
git checkout feat/part-3 && git reset --hard feat/part-2 \
  && git cherry-pick <part-3 commits…>
git push --force-with-lease origin feat/part-1 feat/part-2 feat/part-3
```

Force-push keeps the PRs and their comment history; threads just go *outdated*.

## After the bottom PR merges

How the base PR was merged decides what the next PR needs:

- **Merge commit** (base commits land on `main` as-is): just **retarget** the
  next PR — no rebase. Its diff stays clean because the base commits are now
  shared ancestors on `main`.
  ```bash
  gh pr edit <next-PR> --base main
  ```
- **Squash / rebase merge** (base commits collapse to a new SHA on `main`): the
  next branch still carries the old individual commits, so retargeting shows them
  as a duplicate diff. **Rebase** onto `main`, dropping the merged commits:
  ```bash
  git fetch origin
  git checkout <next-branch> && git rebase --onto origin/main <old-base-tip>
  git push --force-with-lease origin <next-branch>
  gh pr edit <next-PR> --base main
  ```

Detect which happened:

```bash
git fetch origin
git branch -r --contains <base-branch-tip> | grep -q origin/main \
  && echo "MERGE (commits on main as-is — retarget only)" \
  || echo "SQUASH/REBASE (rebase the next branch onto main)"
```

## Merge policy

Drive PRs to a clean review, but **don't merge them yourself** unless that's
explicitly your role — opening, reviewing, fixing, and resolving conversations is
review-only work; the maintainer merges. Confirm before any `git push` to a
protected branch, and never force-push `main`.
