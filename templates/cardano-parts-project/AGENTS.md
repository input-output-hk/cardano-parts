# AGENTS.md — cardano-parts cluster

Guidance for AI agents working in a Cardano cluster repo built from
[cardano-parts](https://github.com/input-output-hk/cardano-parts).

## What this repo is

A deployment of a Cardano cluster: NixOS machine configs (colmena), opentofu/AWS
infrastructure, and sops-encrypted secrets, driven through `just` recipes.

Supported node environments: `mainnet`, `preprod`, `preview`, `dijkstra`, `leios`,
`sanchonet`, `demo`.

## Operating the cluster

Run `just` for the full recipe menu. Common recipes:

- **Nodes**: `just start-node <env>`, `just stop-node <env>`, `just query-tip <env>`,
  `just query-tip-all`.
- **SSH**: `just save-ssh-config`, `just ssh <host>`, `just ssh-list <type> <pattern>`,
  `just ssh-for-each`.
- **Infra**: `just apply <host>` (colmena), `just tofu <workspace> <cmd>` (opentofu),
  `just build-machines`.
- **Governance**: `just vote`, `just vote-with-pool`, `just query-gov-action-status`,
  and the `just update-proposal-*` recipes.
- **db-sync**: `just dbsync-prep`, `just dbsync-psql`, `just dbsync-pool-analyze`.
- **Faucet/pools**: `just dedelegate-pools <env> <idxs>`.

`just lint` runs `deadnix -f` and `statix check`; run it before pushing.

Use `workbench/` for scratch state; it is gitignored.

## Secrets

Secrets are sops-encrypted. Use the `just sops-*` recipes (plus `save-bulk-creds`,
`save-bootstrap-ssh-key`). Key material under `secrets/` is committed, encrypted. Never
commit a plaintext key. The pre-push hook checks encryption.

Encrypted files cannot be handed to `cardano-cli` directly. Decrypt inline into a process
substitution, as the Justfile does: `--signing-key-file <(sops -d path/to.skey)`.

## AI agent skills

This `AGENTS.md` is the canonical instructions file, read directly by Codex and by people.
`.ai/` holds the canonical tool-neutral content; each tool gets a directory of committed
symlinks into it, so `.claude/CLAUDE.md -> ../AGENTS.md` and `.claude/skills -> ../.ai/skills`.
`.claude` is a real directory with everything else in it gitignored, because Claude Code
creates isolated-agent worktrees under `.claude/worktrees/` and those must not land in
tracked content.

Task-specific skills live in `.ai/skills/`; invoke the relevant one before starting that
kind of work:

- **monitoring-query** — query the cluster's Grafana Loki (logs) and Mimir (metrics) via the
  datasource-proxy API; the first stop before on-host access.
- **cluster-ssh** — on-host read-only diagnostics over SRE-opened ControlMaster sockets
  (journalctl, systemctl, zfs, cardano db tools), plus bulk host→host state moves via wush.
  Masters expire, so ask the SRE to reopen rather than assuming a dead socket means a dead host.
- **nushell** — nushell style, best practices and gotchas; invoke before reading or writing
  `.nu` files.
- **pr-description** — draft a PR title and description from the branch's commit diffs.

## Staying in sync with cardano-parts

`just template-diff <file>` and `just template-clone <file>` compare and pull individual
files from upstream cardano-parts.

For a whole batch rather than one file, use the nu script pair. `just upstream-diff-all`
here collects changed template files from cardano-parts and pulls the ones you keep;
`just downstream-diff-all` in cardano-parts does the reverse, porting changes made here
back into the template. Both annotate a candidate list for you to curate in `$EDITOR`
before anything is copied, and both honour a `.upstream-diff-all.excludes` /
`.downstream-diff-all.excludes` file in the downstream repo if present.

Do not pull `.claude` or its contents by either route: the curl fetch returns a symlink's
target as text, replacing the link with a file containing its path.
