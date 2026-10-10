---
name: pr-description
description: Generate a PR title and description by analyzing commit diffs on the current branch. Outputs a pr-description.md file for review. Use when the user asks to write, draft, or generate a PR description, PR summary, or PR title.
---

# PR Description Generator

Generate a PR title and description following the project's established format. See [FORMAT.md](FORMAT.md) for the exact format and an example.

## Workflow

1. Determine the base branch (usually `main`). Run `git log --oneline main..HEAD` to list all commits on the current branch since it diverged.

2. For each commit, run `git show <sha>` to review the full diff. Read every commit — don't skip any. Understand what actually changed, not just what the commit message says.

3. Compile the list of meaningful changes. Exclude trivial items like:
   - Nix formatting (`nixfmt`, `treefmt`, etc.)
   - Typo fixes (unless fixing a typo that caused a real bug)
   - Minor whitespace or comment-only changes
   - Routine file shuffling with no functional impact

4. Write the PR title and description following the format in [FORMAT.md](FORMAT.md).

5. Write the output to `pr-description.md` in the repo root. This is a temporary file for review — the user will copy/paste it into the PR manually.

6. Write a second file `not-included.md` in the repo root listing changes you chose to omit from the description, with a brief reason for each omission (e.g., "nix formatting only", "trivial typo fix").

## Writing rules

- **No leading double spaces.** Lines must not begin with two spaces.
- **Backticks** around file names, variable names, package names, config options, version numbers, and machine names — including in the title.
- **Infinitive tense**: "fix X", "add Y", "bump Z to 1.2" — not "fixes", "adds", "bumps", or "fixed", "added", "bumped".
- **Be concise.** There is already a lot of text in these PRs. Short and to the point. Readers can look at the diffs for details.
- **Don't pad.** No filler phrases like "This PR also includes..." or "Additionally, ...". Just state what changed.
- Ask about anything you're unsure about rather than guessing.
