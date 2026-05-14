---
name: writing-pr-description
description: Generate a PR title and description for cardano-parts releases by analyzing commit diffs on the current branch. Use when the user asks to write, draft, or generate a PR description, release notes, or changelog for this repo.
---

# Writing PR Descriptions for cardano-parts

Generate a PR title and description following the established pattern used in this repo's release PRs. Output is written to a local `pr-description.md` file for review, along with a `not-included.md` file listing minor changes that were intentionally omitted.

## Workflow

1. **Ask the user** two questions before starting:
   - Are there any breaking changes to document? (Usually none.)
   - Are there any known issues to document? (Usually none.)
   - Ask about anything else you're unsure about.

2. **Identify the base branch** this PR targets (usually `main`). Run:
   ```bash
   git log --oneline main..HEAD
   ```

3. **Review each commit's diff** to understand all changes:
   ```bash
   git diff main..HEAD
   ```
   For large diffs, review commit-by-commit:
   ```bash
   git log --oneline main..HEAD
   git show <commit-hash>
   ```

4. **Draft the PR title and description** following the format in [FORMAT.md](FORMAT.md).

5. **Write output files**:
   - `pr-description.md` — the PR title (as an H1) followed by the full description body
   - `not-included.md` — minor changes you chose to omit (formatting fixes, typo corrections, etc.) so the user can review what was left out

## Style Rules

- **Tense**: Use the infinitive ("fix X", "add Y", "bump Z"), not "fixes" or "fixed".
- **Tone**: Short and to the point. Don't be overly wordy — readers will tune out. They can look at the actual changes for details.
- **Formatting**:
  - Surround file names and variable names in backticks (e.g. `flake/colmena.nix`, `tcpTxOpt`).
  - Tables must use actual `|` and `:---:` column separators.
  - Output must NOT have lines led by two spaces (no indented paragraphs).
  - Bold with `**` in the version table ONLY for versions that changed from the previous release.
- **Mithril**: The mithril pre-release is almost always bumped and is typically `unstable`. If there's a problem building the latest unstable, mark it with `**` in the table and add a footnote note explaining the workaround.
- **Omit trivial changes**: Don't mention things like "applied nix formatting" or "fixed typo" unless the typo fix was significant (e.g. fixing an important bug from a prior release). List omitted items in `not-included.md`.
- **Action items / template files**: Every template file modified on this branch should appear in the action items list. Align inline comments using spaces.
- **Key changes bullets**: Each bullet should be a concise summary. Group related changes when it makes sense.

## Reference

See [FORMAT.md](FORMAT.md) for the exact section structure, table format, and examples drawn from previous PRs.
