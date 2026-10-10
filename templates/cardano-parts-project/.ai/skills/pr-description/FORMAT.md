# PR Description Format

## Title

A comma-separated list of the most notable changes, kept under ~80 characters. Use backticks around file names, variable names, package names, and config option names. Use the infinitive tense ("add X", "fix Y", not "adds" or "fixed"). Capitalize the first word only.

Example titles:
- Node `10.6.2`, ng `10.7.0`, zfs AMI, dijkstra respin
- Node `10.6.4`, Dbsync `13.6.0.8`/`13.7.0.2`, zfs ARC cache, buildkite updates
- Node `10.7.1`, Dbsync `13.7.0.4`, Leios testnet

## Description

### Overview

A single dense paragraph summarizing the PR at a high level. Cover the major themes: version bumps, new infrastructure, config changes, monitoring updates, network operations. Keep it concise — readers should get the full picture in one paragraph without needing to read further. Include a statement about including various improvements from cardano-parts <release>.

### Key Changes

A bullet list of the important changes. Each bullet should be one or two sentences max. Group related items into a single bullet when it makes sense.

Guidelines:
- Use backticks for package names, file names, config options, machine names, version numbers
- Use infinitive tense ("bump X to Y", "add Z", "convert A to B")
- Be specific: include version numbers, machine names, config option names
- Don't be overly wordy — readers can look at the actual diffs for details
- Omit trivial changes (formatting, typo fixes, minor cleanup) unless they fix a meaningful bug
- Typically 8-15 bullets depending on PR size

## Example

```markdown
## Overview

This pull request updates cardano-node to release `10.6.4`, while cardano-db-sync moves to `13.6.0.8` with a pre-release at `13.7.0.2`. The ZFS module now supports configurable ARC cache sizing based on percentages. Buildkite infrastructure received updates to support Daedalus Linux CI workflows. Grafana dashboards for cardano-node gained new CPU and memory monitoring panels. Includes various improvements with cardano-parts release `v2026-05-01`.

## Key Changes

* Bump cardano-node to `10.6.3`, then `10.6.4` with release environment deployments
* Update cardano-db-sync to `13.6.0.8` and pre-release to `13.7.0.2` with dbsync deployments
* Extend ZFS AMI module with `boot.zfs.zfsArcPct` option for percentage-based cache configuration
* Resolve buildkite NixOS container startup race condition involving sops
* Add CPU/memory usage monitoring panels and totals to Grafana dashboards
* Update cardano-book documentation for `10.6.3` and `10.6.4` releases
* Execute governance vote on preview network for Van Rossem PV11 cost model update
* Incorporate cardano-parts release `v2026-04-15` improvements
```
