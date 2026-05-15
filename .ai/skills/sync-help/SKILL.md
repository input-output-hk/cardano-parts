---
name: sync-help
description: Prints a quick reference for the sync skill suite (sync-status, sync-execute). Use when the user asks how to use the sync skills or needs a reminder of the workflow.
---

# Sync Help

Output the following help text:

---

## Sync Skills Quick Reference

### Typical workflow

1. `/sync-status` — See which downstream repos have diverged from templates.
2. `/sync-execute upstream` — Walk through each change, decide whether to
   upstream it into templates. One file at a time, with commit pauses.
3. `/pr-description` — Generate the PR description for the upstream changes.
4. `/sync-execute downstream` — Walk through each template change, decide
   whether to downstream it. One file at a time, with commit pauses.

Always complete all upstreaming and the PR description before downstreaming.

### Setup

Copy the example config and fill in your downstream repo paths:

```
cp .ai/skills/sync-review/sync-config.example.json .ai/skills/sync-review/sync-config.local.json
```

Paths can be relative (from repo root) or absolute. The config is gitignored.

### Responding to diffs

During `/sync-execute`, the AI shows each diff and waits for your decision:

- **"yes"** — apply this change
- **"no"** — skip it
- **"no, exclude"** — skip and permanently exclude this file path
- **"no, add rule"** — skip and add a classification rule for future cycles
- **"show more context"** — see a wider diff
- Or give any specific instruction

### Excludes and rules

Each repo in the config has two arrays for persistent decisions:

- `"exclude"` — glob patterns for files to silently skip (e.g., `"mdbook/**"`)
- `"rules"` — auto-classify specific files or hunks with a reason

These are saved per-repo in `sync-config.local.json` and automatically applied
in future sync cycles.

### Config file (gitignored, in `.ai/skills/sync-review/`)

| File | Purpose |
|---|---|
| `sync-config.local.json` | Repo paths, excludes, classification rules |

### Tips

- `/sync-execute` requires a direction: `upstream` or `downstream`.
- The AI always waits for your response before proceeding to the next file.
- `/sync-status` is read-only and safe to run anytime.
- All skills only examine files that changed on the current branch in any repo.
