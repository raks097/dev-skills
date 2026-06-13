# dev-skills

Reusable, developer-agnostic workflow [agent skills](https://agentskills.io),
installable with [`qvr`](https://github.com/astra-sh/qvr). This repo is a qvr
registry (skills live under `skills/`; see `qvr.toml`).

```bash
# add this repository as a registry, then install a skill:
qvr registry add <url-of-this-repo>
qvr add greptile-review-loop
```

## Skills

| Skill | What it does |
|-------|--------------|
| [`greptile-review-loop`](skills/greptile-review-loop/) | Drive a GitHub PR (or a stacked PR series) through Greptile bot reviews to a clean 5/5 — read findings, fix, reply to + resolve each review conversation, close/reopen to re-trigger, repeat. |
