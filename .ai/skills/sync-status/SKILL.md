---
name: sync-status
description: Shows a summary table of divergence between cardano-parts templates and configured downstream repos, with per-file one-liner descriptions. Use to get a quick overview of sync state before or during a sync cycle.
---

# Sync Status

## Configuration

Uses `.ai/skills/sync-review/sync-config.local.json`.

## Workflow

1. **Load config**. If missing, tell the user to create one.

2. **Build the changed-files list**. Union of all files changed on the current
   branch (vs base branch) across upstream and every configured downstream:
   ```
   git diff --name-only <base-branch>...HEAD
   ```
   Auto-detect base branch per repo (`main` or `master`), or use the
   `"base_branch"` config override. Only these files are examined.

3. **Process one repo at a time**. For each downstream repo, apply that repo's
   `"exclude"` patterns to remove files, then compare the remaining files from
   the changed-files list against `templates/cardano-parts-project/`:
   - Count files that differ
   - Count files excluded by rules
   - Count files only in downstream
   - Count files only in template

4. **Output a summary table**:

   ```
   Sync Status (as of <date>)
   Template path: templates/cardano-parts-project
   Changed files in union list: 23

   Repo                    | Diverged | Excluded | Down-Only | Tmpl-Only
   ------------------------|----------|----------|-----------|----------
   cardano-playground      |       12 |        4 |         8 |         0
   ouroboros-network-ops   |        5 |        0 |         3 |         1
   ```

5. **Per-file detail**, one repo at a time. For every file from the
   changed-files list (excluding excluded files), include a short one-liner
   (under ~40 chars) hinting at what changed — a module name, script name,
   function name, or brief description like "alloy recording rules". Generate
   by scanning diff hunks for the most prominent changed symbol.

   ```
   cardano-playground — Changed Files (4 excluded by rules):
     flake/colmena.nix                  machine instance defs
     flake/nixosModules/common.nix      alloy config helper
     scripts/bash-fns.sh                sops_config fn fix
     Justfile                           new dedelegate recipe
   ```

   **IMPORTANT**: After showing each repo's detail, STOP and WAIT for the user
   to respond before continuing to the next repo. Do not proceed without user
   input.

## Important Notes

- Read-only — never modifies files.
- Unavailable repo paths show as "unavailable" rather than erroring.
- If a repo has `"rules"` or `"exclude"` entries in the config, note the
  counts in the per-repo detail.
