---
name: sync-review
description: Scans selected downstream repos against cardano-parts templates, diffs changed files, and classifies each change as upstream-worthy, downstream-only, or needs-discussion. Use when starting a sync cycle or when the cardano-parts maintainer wants to review what has diverged between upstream templates and downstream repos.
---

# Sync Review

## Configuration

Reads `.ai/skills/sync-review/sync-config.local.json` for downstream repo
paths. Copy `sync-config.example.json` to create it. Paths can be relative
(from repo root) or absolute. The config is gitignored.

If the config doesn't exist, prompt the user to create one or accept a
downstream repo path as an argument.

## Workflow

1. **Load config** from `.ai/skills/sync-review/sync-config.local.json`.

2. **Load memory** from `.ai/skills/sync-review/memory.local.json` (if it
   exists). This contains persistent classification decisions from prior sync
   cycles. Apply matching rules automatically and note which rule matched in
   the output.

3. **Select target**: Use the repo the user specifies, or offer to review all
   configured repos.

4. **Enumerate changed files** for each downstream repo vs
   `templates/cardano-parts-project/`:
   - Files that exist in both but differ
   - Files only in downstream (potential new template files)
   - Files only in upstream (not yet cloned or deleted downstream)

5. **Diff and classify** each changed file. For each meaningful hunk, classify:

   **Upstream candidates** (useful to all downstream consumers):
   - Helper functions, library code, modules, bug fixes
   - Just recipes that are generally useful
   - Monitoring improvements (dashboards, alerts, recording rules)
   - Infrastructure patterns (opentofu, cloudformation)
   - Cost models, SQL scripts, Python library code
   - Secret management pattern improvements
   - Template structural improvements

   **Downstream-only** (specific to that repo):
   - Machine/instance definitions in `colmena.nix`, `nixosConfigurations.nix`
   - Repo-specific NixOS modules for services unique to that deployment
   - IP addresses, hostnames, domain names
   - Secret values/paths tied to that deployment
   - Environment-specific config beyond the standard set
   - Repo-specific CI/CD configuration
   - Custom scripts in repo-specific subdirectories (e.g., `scripts/playground/`)

   **Needs discussion**:
   - Hunks mixing upstream-worthy and downstream-specific content
   - Modules that could be general-purpose but are only used by one deployment
   - Changes to shared files where intent is ambiguous

6. **Output a structured report**:

   ```
   ## Sync Review: <repo-name>

   ### Summary
   - X files changed, Y upstream, Z downstream-only, W need discussion
   - N files only in downstream

   ### Upstream Candidates
   - File path, brief description, diff (or relevant hunks if large)

   ### Needs Discussion
   - File path, why it's unclear, diff

   ### Downstream-Only (for reference)
   - File paths with one-line descriptions

   ### New Downstream Files (not in template)
   - File paths with recommendation on whether to add to template
   ```

7. **Save state** to `.ai/skills/sync-review/state.local.json`:
   ```json
   {
     "timestamp": "ISO-8601",
     "upstream_repo": "cardano-parts",
     "upstream_branch": "current-branch",
     "reviews": {
       "repo-name": {
         "path": "/absolute/path",
         "upstream_candidates": [
           {
             "file": "relative/path",
             "description": "what changed",
             "status": "pending"
           }
         ],
         "downstream_only": [],
         "needs_discussion": [],
         "new_files": []
       }
     }
   }
   ```

## User Interaction

- After presenting the report, ask if the user wants to reclassify any items.
- Accept corrections like "move X to upstream" or "that's downstream-only".
- Update the state file with reclassifications.
- If the user says a decision is permanent ("never upstream that", "always skip
  this"), record it in `.ai/skills/sync-review/memory.local.json`.

## Memory File

Persistent classification decisions in `.ai/skills/sync-review/memory.local.json`
(gitignored, local to each developer):

```json
{
  "rules": [
    {
      "pattern": "flake/nixosModules/buildkite/*",
      "classification": "downstream-only",
      "reason": "buildkite modules are playground-specific",
      "added": "2026-05-14"
    },
    {
      "file": "flake/colmena.nix",
      "hunk_match": "machine definitions",
      "classification": "downstream-only",
      "reason": "instance definitions are always repo-specific",
      "added": "2026-05-14"
    }
  ]
}
```

Rules match by `pattern` (glob) or `file` + `hunk_match` (for mixed files).
Always note which rule matched so the user can verify correctness.

## Classification Notes

- When in doubt, classify as "needs-discussion".
- Large files (JSON dashboards, cost models): summarize the diff, note if it's
  a version bump vs structural change.
- Mixed files (upstream + downstream hunks): flag as "needs-discussion".
- `Justfile`: frequent source of both kinds of changes — classify carefully.
- `flake/opentofu/grafana/`: often upstream candidates.
- `flake/nixosModules/`: case-by-case — some are general infrastructure,
  others are deployment-specific.
