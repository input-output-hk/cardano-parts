---
name: sync-status
description: Shows a summary table of divergence between cardano-parts templates and all configured downstream repos, with per-file one-liner descriptions. Use to get a quick overview of sync state before or during a sync cycle.
---

# Sync Status

## Configuration

Uses `.ai/skills/sync-review/sync-config.local.json` (same as sync-review).

## Workflow

1. **Load config**. If missing, tell the user to create one.

2. **For each downstream repo**, compare files against
   `templates/cardano-parts-project/`:
   - Count files that differ
   - Count files only in downstream
   - Count files only in template
   - If `state.local.json` exists, show reviewed/applied/pending counts

3. **Output a summary table**:

   ```
   Sync Status (as of <date>)
   Template path: templates/cardano-parts-project
   Memory rules active: 12

   Repo                    | Diverged | Downstream-Only | Template-Only | Reviewed | Applied
   ------------------------|----------|-----------------|---------------|----------|--------
   cardano-playground      |       12 |               8 |             0 |     12/12|    7/12
   ouroboros-network-ops   |        5 |               3 |             1 |      0/5 |     0/5
   ```

4. **Per-file detail** for each repo. For every diverged file, include a short
   one-liner (under ~40 chars) hinting at what changed — a module name, script
   name, function name, or brief description like "alloy recording rules".
   Generate by scanning diff hunks for the most prominent changed symbol.

   ```
   cardano-playground — Diverged Files:
     flake/colmena.nix                  downstream-only    machine instance defs
     flake/nixosModules/common.nix      upstream (applied)  alloy config helper
     scripts/bash-fns.sh                upstream (pending)   sops_config fn fix
     Justfile                           needs-discussion     new dedelegate recipe
   ```

## Important Notes

- Read-only — never modifies files.
- Unavailable repo paths show as "unavailable" rather than erroring.
- "Reviewed" and "Applied" columns only appear if a state file exists.
- If `memory.local.json` exists, show the rule count at the top.
