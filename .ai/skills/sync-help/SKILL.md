---
name: sync-help
description: Prints a quick reference for the sync skill suite (sync-status, sync-review, sync-execute). Use when the user asks how to use the sync skills or needs a reminder of the workflow.
---

# Sync Help

Output the following help text:

---

## Sync Skills Quick Reference

### Typical workflow

1. `/sync-status` — See which downstream repos have diverged from templates.
2. `/sync-review` — Classify each change as upstream, downstream-only, or needs-discussion.
3. `/sync-execute` — Apply changes one at a time with suggested commit messages.

### Setup

Copy the example config and fill in your downstream repo paths:

```
cp .ai/skills/sync-review/sync-config.example.json .ai/skills/sync-review/sync-config.local.json
```

Paths can be relative (from repo root) or absolute. The config is gitignored.

### Persistent memory

During `/sync-review`, tell the AI to remember classification decisions permanently:

- "never upstream that, remember it"
- "scripts/playground/ is always downstream-only, record that"
- "buildkite modules are always downstream-only"

Saved to `.ai/skills/sync-review/memory.local.json`, automatically applied in
future sync cycles.

### Local files (all gitignored, all in `.ai/skills/sync-review/`)

| File | Purpose |
|---|---|
| `sync-config.local.json` | Your downstream repo paths |
| `state.local.json` | Current sync cycle review/apply state |
| `memory.local.json` | Persistent classification decisions across cycles |

### Tips

- `/sync-review <repo-name>` to review a single repo.
- `/sync-execute upstream` or `/sync-execute downstream` to limit direction.
- The AI pauses after each change during `/sync-execute` for you to review,
  stage, and commit.
- `/sync-status` is read-only and safe to run anytime.
