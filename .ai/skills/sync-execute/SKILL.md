---
name: sync-execute
description: Walks through each changed file one at a time, showing the diff and asking the user whether to apply it. Requires "upstream" or "downstream" argument. Use after sync-status to begin applying changes between cardano-parts templates and downstream repos.
---

# Sync Execute

**Requires an argument**: `/sync-execute upstream` or `/sync-execute downstream`.
If no argument is provided, ask the user which direction and WAIT for a response.

## Configuration

Uses `.ai/skills/sync-review/sync-config.local.json`.

## Workflow

1. **Load config** from `.ai/skills/sync-review/sync-config.local.json`.

2. **Determine direction** from the argument. If missing, ask and WAIT.

3. **Build the changed-files list**. Union of all files changed on the current
   branch (vs base branch) across upstream and every configured downstream:
   ```
   git diff --name-only <base-branch>...HEAD
   ```
   Auto-detect base branch per repo (`main` or `master`), or use the
   `"base_branch"` config override.

4. **Process one repo at a time**. For each repo:
   - Apply `"exclude"` patterns to remove files from consideration
   - Apply `"rules"` to auto-skip files with existing classifications (note
     which rule matched)
   - Work through remaining files one by one

5. **For each file**, follow the direction-specific workflow below.

## Showing Diffs

At the start of the session, before processing any files, ask the user for
their terminal column width. Suggest they run `tput cols` in another shell
and paste the result. Use their answer as the `--cols` value for all icdiff
commands. If they don't answer, default to 180.

Do NOT run the diff command yourself. Instead, print the command for the user
to run with the `!` prefix. Downstream file on LEFT, template on RIGHT:

```
! icdiff --cols=<width> <downstream-file> <template-file>
```

The user will run it, see the output in their terminal, then answer your
question about what to do with the file.

This produces a side-by-side color diff with the full output printed inline.

### `/sync-execute upstream` (downstream -> cardano-parts templates)

This includes BOTH files that differ between downstream and template AND files
that only exist downstream (which the user may want to add to the template).
For downstream-only files, note that there is no template counterpart and show
the file contents instead of a diff.

For each file, one at a time:

a. If the file exists in both repos, show the diff using icdiff (downstream on
   left, template on right). If the file only exists downstream, show its
   contents and note it's a new file not yet in the template.
b. **Ask the user** what to do and **WAIT for their response**. Do NOT
   proceed without an answer. Accepted responses:
   - **"yes"** / **"y"** — apply this change to the template
   - **"no"** / **"n"** — skip this file
   - **"no, exclude"** — skip and add the file path to this repo's `"exclude"`
     array in `sync-config.local.json`
   - **"no, add rule"** — skip and prompt for a rule description, then add to
     this repo's `"rules"` array in `sync-config.local.json`
   - **"show more context"** — show a wider diff
   - Any other instruction — follow it (e.g., "only upstream the helper
     function, not the machine definition")
c. If "yes": apply the changes to the template file. If the change references
   deployment-specific values (machines, IPs), comment out or generalize those
   to keep the template valid for all consumers.
d. Suggest a commit message matching the repo's conventions
   (check `git log --oneline -20`).
e. **WAIT** for the user to review, stage, and commit. Do NOT proceed until
   the user confirms they are ready for the next file.

### `/sync-execute downstream` (templates -> downstream repos)

This includes BOTH files that differ between template and downstream AND files
that only exist in the template (which the user may want to add to the
downstream repo). For template-only files, note that there is no downstream
counterpart and show the file contents instead of a diff.

For each file, one at a time:

a. If the file exists in both repos, show the diff using icdiff (downstream on
   left, template on right). If the file only exists in the template, show its
   contents and note it's a new file not yet in the downstream repo.
b. **Ask the user** what to do and **WAIT for their response**. Do NOT
   proceed without an answer. Same response options as upstream.
c. If "yes": apply the template change to the downstream file.
d. Suggest a commit message matching the downstream repo's conventions
   (check `git log --oneline -20` in that repo).
e. **WAIT** for the user to review, stage, and commit. Do NOT proceed until
   the user confirms they are ready for the next file.

6. **After each repo is complete**, show a summary of what was applied,
   skipped, excluded, and ruled out. Then **WAIT** before moving to the next
   repo.

7. **After all upstream work is done**, remind the user to run
   `/pr-description` to generate the PR description for the upstream changes
   before starting any downstream work.

## Critical: Always Wait for User Input

**NEVER proceed to the next file or repo without explicit user confirmation.**
Every diff shown requires a response. Every commit pause requires confirmation.
If in doubt, ask and wait. This is the most important rule of this skill.

## Important Notes

- Do not `git add` or `git commit` — the user handles staging and committing.
- One standalone change at a time. Suggest a commit message, then wait.
- When upstreaming nix code with specific machines/IPs, replace with
  example/placeholder values or comment them out.
- When upstreaming modules, ensure imports are added to the template structure.
- If a patch fails to apply cleanly, show the conflict — don't guess.
- Work in the current branch. Don't create new branches.
- For large files (JSON dashboards), prefer full file replacement over merging.
- When writing excludes or rules to `sync-config.local.json`, do NOT use
  Claude's general memory system. All sync decisions go in the config file.
