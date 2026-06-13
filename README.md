# dev-skills

Reusable developer-workflow [agent skills](https://agentskills.io), installable with
[`qvr`](https://github.com/astra-sh/qvr).

```bash
qvr registry add https://github.com/raks097/dev-skills
qvr add greptile-review-loop
```

## Skills

| Skill | What it does |
|-------|--------------|
| [`greptile-review-loop`](greptile-review-loop/) | Drive a GitHub PR (or a stacked PR series) through Greptile bot reviews to a clean 5/5 — read findings, fix, reply to + resolve each review conversation, close/reopen to re-trigger, repeat. |
