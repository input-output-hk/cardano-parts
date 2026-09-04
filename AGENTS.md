# AGENTS.md — cardano-parts

Guidance for AI agents working on the **cardano-parts** repository itself. For agents
operating a *downstream* cluster built from this repo, see
`templates/cardano-parts-project/AGENTS.md`.

## What this repo is

cardano-parts is a [flake-parts](https://flake.parts) library of Nix/NixOS modules for
deploying and operating Cardano clusters. It exports reusable flakeModules and NixOS
profiles, and ships a downstream project template consumed via
`nix flake new -t github:input-output-hk/cardano-parts <dir>`.

## Layout

- `flakeModules/` — the flake-parts modules exported to downstreams: `cluster.nix`,
  `shell.nix` (devShell + pre-push hook), `jobs.nix` (cardano ops job derivations),
  `entrypoints.nix`, `process-compose.nix`, `aws.nix`, `pkgs.nix`, `lib.nix`.
- `flake/` — internal flake wiring: `nixosModules/` (deployable profiles),
  `templates.nix` (the downstream template output), `hydraJobs.nix`, `lib.nix`.
- `templates/cardano-parts-project/` — the downstream scaffold: its own `Justfile`,
  `scripts/recipes/*.just`, and `.ai/skills/`. Edits here ship to downstreams.
- `perSystem/`, `scripts/`, `docs/`.

## Dev workflow

- Enter the devShell: `nix develop` (or `direnv allow`). Run `just` for the recipe menu.
- Format: `nix fmt` — treefmt runs `alejandra` on `*.nix`/`*.nix-import` and `nufmt` on `*.nu`.
- Lint: `just lint` (`deadnix -f`, `statix check`). Full gate: `nix flake check`.
- A pre-push git hook (auto-linked by the devShell) checks secrets encryption, lint, and format.

## Conventions

- In `flakeModules/jobs.nix`, keep each recipe's `# Inputs:` env-var doc block intact even
  when the local block doesn't reference every listed var.
- The template `Justfile` sets `set shell := ["bash", "-uc"]`; most recipes are shebang
  recipes (`#!/usr/bin/env bash` + `set -euo pipefail`, or `#!/usr/bin/env nu`).

## AI agent config

`.ai/` is the canonical agent-config dir; `.claude` is a committed symlink to it. This
`AGENTS.md` is the canonical instructions file; `.ai/CLAUDE.md` symlinks to it so Claude
Code loads it via `.claude/CLAUDE.md`. Repo-dev skills live in `.ai/skills/`: `gha`,
`nushell`, `pr-description`, and the `sync-status`/`sync-execute`/`sync-help` suite for
template↔downstream syncing.
