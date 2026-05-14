---
name: sync-execute
description: Applies upstream and downstream patches one at a time based on a prior sync-review, suggesting commit messages and pausing for user review between each change. Use after running sync-review to act on classified changes.
---

# Sync Execute

## Configuration

Uses `.ai/skills/sync-review/sync-config.local.json` (same as sync-review).

## Workflow

1. **Load state** from `.ai/skills/sync-review/state.local.json`. If missing
   or stale, tell the user to run `/sync-review` first.

2. **Confirm scope**: Show a summary of what will be patched and ask for
   confirmation.

3. **Upstream patching** (downstream -> cardano-parts templates):

   For each file classified as "upstream" with status "pending":

   a. Read the downstream file and the corresponding template file.
   b. Identify relevant hunks (skip downstream-specific hunks in mixed files).
   c. Apply the changes to the template file.
   d. If the change references deployment-specific values (machines, IPs),
      comment out or generalize those to keep the template valid.
   e. Suggest a commit message matching the repo's conventions
      (check `git log --oneline -20`).
   f. **Pause and wait** for the user to review, stage, and commit.
      Do not proceed until the user confirms.
   g. Update the state file to mark the item as "applied".

4. **Downstream patching** (templates -> downstream repos):

   For each downstream repo, compare current templates against downstream files:

   a. Show the diff to the user.
   b. Ask if they want to apply it.
   c. Apply the change.
   d. Suggest a commit message matching the downstream repo's conventions
      (check `git log --oneline -20` in that repo).
   e. **Pause and wait** for the user to review, stage, and commit.
      Do not proceed until the user confirms.
   f. Update the state file.

5. **Report**: Summarize what was applied, skipped, and remaining.

## Direction Control

- `/sync-execute upstream` — only upstream into templates
- `/sync-execute downstream` — only downstream from templates
- `/sync-execute` — both, upstream first

## Important Notes

- Always show the diff before applying.
- Do not `git add` or `git commit` — the user handles staging and committing.
- One standalone change at a time. Suggest a commit message, then wait. This
  produces clean, compartmentalized commit history.
- When upstreaming nix code with specific machines/IPs, replace with
  example/placeholder values or comment them out.
- When upstreaming modules, ensure imports are added to the template structure.
- If a patch fails to apply cleanly, show the conflict — don't guess.
- Work in the current branch. Don't create new branches.
- For large files (JSON dashboards), prefer full file replacement over merging.
