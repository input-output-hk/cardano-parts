# AGENTS.md — cardano-parts cluster

Guidance for AI agents working in a Cardano cluster repo built from
[cardano-parts](https://github.com/input-output-hk/cardano-parts).

## What this repo is

A deployment of a Cardano cluster: NixOS machine configs (colmena), opentofu/AWS
infrastructure, and sops-encrypted secrets, driven through `just` recipes.

## Operating the cluster

Run `just` for the full recipe menu. Common recipes:

- **Nodes**: `just start-node <env>`, `just stop-node <env>`, `just query-tip <env>`,
  `just query-tip-all`.
- **SSH**: `just save-ssh-config`, `just ssh <host>`, `just ssh-list <type> <pattern>`,
  `just ssh-for-each`.
- **Infra**: `just apply` / `just tofu <workspace> <cmd>` (opentofu), `just build-machines`.
- **Governance**: `just vote`, `just vote-with-pool`, `just query-gov-action-status`,
  and the `just update-proposal-*` recipes.
- **db-sync**: `just dbsync-prep`, `just dbsync-psql`, `just dbsync-pool-analyze`.
- **Faucet/pools**: `just dedelegate-pools <env> <idxs>`.

Supported node environments: `mainnet`, `preprod`, `preview`, `dijkstra`, `leios`,
`sanchonet`, `demo`.

## Secrets

Secrets are sops-encrypted. Use the `just sops-*` recipes (plus `save-bulk-creds`,
`save-bootstrap-ssh-key`). Never commit plaintext keys — `*.skey`, `*.vkey`, `*.mnemonic`
and similar are gitignored, and the pre-push hook checks encryption.

## AI agent skills

`.ai/` is the canonical agent-config dir (`.claude` symlinks to it). Task-specific skills
live in `.ai/skills/`; invoke the relevant one before starting that kind of work:

- **cluster-ssh** — on-host read-only diagnostics over SRE-opened ControlMaster sockets
  (journalctl, systemctl, zfs, cardano db tools), plus bulk host→host state moves via wush.
- **monitoring-query** — query the cluster's Grafana Loki (logs) and Mimir (metrics) via the
  datasource-proxy API; the first stop before on-host access.
- **nushell** — nushell v0.112 style, best practices, and gotchas; invoke before reading or
  writing `.nu` files.
- **pr-description** — draft a PR title and description from the branch's commit diffs.

## Staying in sync with cardano-parts

`just template-diff <file>` and `just template-clone <file>` compare/pull individual files
from upstream cardano-parts. Note: `.claude` is a committed symlink and must not be pulled
via `template-clone` — the curl fetch would replace it with a text file containing its target.
