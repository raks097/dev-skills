#!/usr/bin/env python3
"""Greptile webhook receiver — wake on review events instead of polling.

A tiny stdlib-only HTTP server (no pip installs) that receives GitHub webhook
deliveries, keeps only Greptile's review activity, and appends one compact JSON
line per relevant event to an events file the review loop tails. This replaces
"poll every N seconds" with "react when an event lands".

Events kept (sender == greptile-apps[bot]):
  - pull_request_review        -> Greptile submitted/edited an inline review (carries commit_id)
  - issue_comment              -> Greptile created/edited its summary comment (carries the score)

Each emitted line looks like:
  {"ts":"...","pr":5,"kind":"review","action":"submitted","commit":"abc123","score":"5/5"}

Usage:
  GREPTILE_EVENTS=/tmp/greptile-events.jsonl \\
  WEBHOOK_SECRET=<same secret you set on the repo webhook> \\
  python3 webhook-receiver.py [--port 8099] [--path /webhook]

Env:
  GREPTILE_EVENTS  output file (default: /tmp/greptile-events.jsonl)
  WEBHOOK_SECRET   if set, X-Hub-Signature-256 is verified and bad signatures are rejected
  BOT_LOGIN        sender login to keep (default: greptile-apps[bot])

Expose it to GitHub with a tunnel (pick one):
  npx smee-client --url https://smee.io/<channel> --target http://127.0.0.1:8099/webhook
  ngrok http 8099            # then use the https URL + /webhook as the payload URL
See references/webhook-mode.md for the full setup, including the gh command that
creates the repo webhook.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVENTS = os.environ.get("GREPTILE_EVENTS", "/tmp/greptile-events.jsonl")
SECRET = os.environ.get("WEBHOOK_SECRET", "").encode()
BOT = os.environ.get("BOT_LOGIN", "greptile-apps[bot]")
SCORE_RE = re.compile(r"Confidence Score:\s*([0-9])/5", re.I)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _verify(body: bytes, sig: str | None) -> bool:
    if not SECRET:
        return True  # no secret configured -> accept (dev only)
    if not sig or not sig.startswith("sha256="):
        return False
    mac = hmac.new(SECRET, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest("sha256=" + mac, sig)


def _extract(event: str, payload: dict) -> dict | None:
    """Map a GitHub delivery to a compact event line, or None to ignore it."""
    sender = (payload.get("sender") or {}).get("login")
    if sender != BOT:
        return None
    if event == "pull_request_review":
        pr = (payload.get("pull_request") or {}).get("number")
        review = payload.get("review") or {}
        body = review.get("body") or ""
        m = SCORE_RE.search(body)
        return {"ts": _now(), "pr": pr, "kind": "review",
                "action": payload.get("action"), "commit": review.get("commit_id"),
                "score": (m.group(1) + "/5") if m else None}
    if event == "issue_comment":
        issue = payload.get("issue") or {}
        if "pull_request" not in issue:  # only PR comments
            return None
        body = (payload.get("comment") or {}).get("body") or ""
        m = SCORE_RE.search(body)
        return {"ts": _now(), "pr": issue.get("number"), "kind": "comment",
                "action": payload.get("action"), "commit": None,
                "score": (m.group(1) + "/5") if m else None}
    return None


class Handler(BaseHTTPRequestHandler):
    PATH = "/webhook"

    def log_message(self, *_):  # quiet default logging
        pass

    def do_POST(self):  # noqa: N802
        if self.path.rstrip("/") != self.PATH.rstrip("/"):
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        if not _verify(body, self.headers.get("X-Hub-Signature-256")):
            self.send_response(401); self.end_headers(); return
        event = self.headers.get("X-GitHub-Event", "")
        try:
            payload = json.loads(body or b"{}")
        except json.JSONDecodeError:
            self.send_response(400); self.end_headers(); return
        line = _extract(event, payload)
        if line is not None:
            with open(EVENTS, "a") as f:
                f.write(json.dumps(line) + "\n")
            print(json.dumps(line), flush=True)
        self.send_response(204); self.end_headers()

    def do_GET(self):  # noqa: N802 — health check
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"greptile webhook receiver: ok\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--path", default="/webhook")
    args = ap.parse_args()
    Handler.PATH = args.path
    print(f"receiver on :{args.port}{args.path} -> {EVENTS} "
          f"(secret {'set' if SECRET else 'UNSET — dev only'})", file=sys.stderr)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
