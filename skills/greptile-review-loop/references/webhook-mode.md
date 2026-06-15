# Webhook mode (opt-in) — wake on review events instead of polling

Polling (`scripts/poll-score.sh`) hits the API on a timer. Webhook mode flips
that around: GitHub pushes review events to a small local receiver the moment
they happen, and the loop blocks on those events. Lower latency, no busy-wait,
no rate-limit pressure from rapid PR churn.

The cost is one piece of standing infrastructure: GitHub needs a **public URL**
to POST to, so a local receiver must be exposed through a tunnel. If you can't
run a tunnel, stay on polling — it needs nothing.

## How the pieces fit

```
GitHub webhook ──POST──▶ tunnel (smee/ngrok) ──▶ webhook-receiver.py
                                                      │ appends one JSON line per event
                                                      ▼
                                          $GREPTILE_EVENTS (jsonl)
                                                      ▲
                          await-review.sh tails it ───┘  (blocks until PR@head is re-reviewed)
```

## One-time setup

1. **Start the receiver** (stdlib only, no installs):
   ```bash
   export GREPTILE_EVENTS=/tmp/greptile-events.jsonl
   export WEBHOOK_SECRET=$(openssl rand -hex 20)      # remember this value
   python3 scripts/webhook-receiver.py --port 8099 &
   ```

2. **Expose it** with a tunnel (pick one):
   ```bash
   # Option A — smee (no account; gives a stable channel URL)
   npx smee-client --url https://smee.io/<new-channel> --target http://127.0.0.1:8099/webhook
   # Option B — ngrok
   ngrok http 8099            # use the printed https URL, with /webhook appended
   ```
   Call the resulting public payload URL `$HOOK_URL` (e.g. `https://smee.io/<channel>`
   for smee, or `https://<id>.ngrok.app/webhook` for ngrok).

3. **Register the webhook on the repo** (needs admin on the repo):
   ```bash
   OWNER=astra-sh REPO=agora
   gh api -X POST repos/$OWNER/$REPO/hooks \
     -f name=web -F active=true \
     -f 'events[]=pull_request_review' -f 'events[]=issue_comment' \
     -f config[url]="$HOOK_URL" \
     -f config[content_type]=json \
     -f config[secret]="$WEBHOOK_SECRET"
   ```
   `pull_request_review` carries Greptile's inline-review `commit_id`;
   `issue_comment` carries the edited summary (and its `Confidence Score`).

## Using it in the loop

Replace the "poll for the new score" step with a blocking wait keyed to the
exact head commit you just pushed:

```bash
HEAD=$(git rev-parse HEAD)
scripts/await-review.sh "$PR" "$HEAD"     # returns when Greptile re-reviews $HEAD
# then read the full review/threads via the usual gh/GraphQL queries
```

`await-review.sh` exits as soon as a `pull_request_review` event for the PR at
`$HEAD` lands (or prints `timeout` after its deadline). The receiver also logs
each kept event to stdout, so `tail -f $GREPTILE_EVENTS` is a live feed.

## Notes / gotchas

- **Set `WEBHOOK_SECRET`.** Without it the receiver accepts any POST (dev only);
  with it, deliveries are HMAC-verified (`X-Hub-Signature-256`) and forgeries
  rejected. Use the same value in the `gh api` call above.
- **Still close/reopen to re-trigger.** Webhook mode changes how you *learn* a
  review happened, not how you *cause* one — a push often doesn't re-run
  Greptile, so the close/reopen step (`scripts/retrigger.sh`) stays.
- **Summary edits have no commit.** Greptile edits its summary comment in place;
  that `issue_comment` carries the score but not a commit SHA, so `await-review.sh`
  keys on the `pull_request_review` event (which does carry `commit_id`) for the
  precise "this head was reviewed" signal.
- **Verify delivery** if events never arrive: `gh api repos/$OWNER/$REPO/hooks`
  then check the hook's recent deliveries in the GitHub UI (Settings → Webhooks),
  and confirm the tunnel target is `…/webhook`.
- **Teardown:** `gh api -X DELETE repos/$OWNER/$REPO/hooks/<id>`, stop the tunnel,
  kill the receiver.
