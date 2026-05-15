# PR Description Format Reference

This file documents the exact structure and conventions used in cardano-parts release PR descriptions, derived from PRs #79, #81, and #82.

## PR Title

Short, version-focused. List the most notable component bumps. Examples:

- "Node 10.6.2, ng 10.7.0, zfs AMI, dashes"
- "Node 10.6.4, Dbsync 13.6.0.8/13.7.0.2, zfs ARC cache"
- "Node 10.7.1, Dbsync 13.7.0.4, Mithril 2617.0"

Pattern: `Node <version>[, Dbsync <rel>/<pre>][, other notable features]`

The title can also mention 1-2 significant non-version features if they're a major part of the release (e.g. "zfs AMI", "zfs ARC cache").

## PR Description Body

### Section 1: Overview

A single paragraph summarizing the release at a high level. Mention the key version bumps and 2-3 of the most significant changes. End with "Other miscellaneous improvements and fixes are detailed below." if there are many smaller changes.

Example:
```
### Overview:

This release updates cardano-node to `10.6.4`, cardano-db-sync to `13.6.0.8`, and cardano-db-sync pre-release to `13.7.0.2`. Nix has been bumped to address security vulnerabilities `GHSA-g3g9-5vj6-r3gj` and `CVE-2026-39860`. The ZFS AMI module gains a configurable option for percentage-based ARC cache sizing derived from the node RAM. Various template recipe improvements, script fixes, and Grafana dashboard enhancements are also included.
```

### Section 2: Details (Version Table)

Intro line: "Important versioning updates in this release are underlined:" (they use `**bold**` in markdown to indicate changes).

The table lists ALL components with their current release and pre-release versions. Bold (`**`) ONLY the versions that changed from the prior release.

```
| Component | Release | Pre-release |
|:---:|:---:|:---:|
| blockperf | 2.0.3 | N/A |
| cardano-address | 4.0.2 | N/A |
| cardano-cli | **10.16.0.0** | **10.16.0.0** |
| cardano-db-sync | **13.7.0.4** | **13.7.0.4** |
| cardano-faucet | 10.6 | 10.6 |
| cardano-node | **10.7.1** | **10.7.1** |
| cardano-ogmios | 6.14.0 | N/A |
| cardano-signer | 1.34.0 | N/A |
| cardano-wallet | v2025-12-15 | N/A |
| credential-manager | 0.1.5.0 | N/A |
| mithril | **2617.0** | **unstable** |
| nix* | 2.33.5 | N/A |
| nixpkgs* | 25.11 | N/A |
```

After the table, add footnotes as needed:

```
\* = For nixos machine deployments
\*\* = Current mithril unstable tag does not nix build; release version substituting
```

The `**` footnote is only used when mithril unstable is broken and the release version is substituted.

### Section 3: Key Changes

A bullet list of all notable changes, using the infinitive tense. Start each bullet with a dash `-`. Group version bumps first, then other changes roughly by category.

```
### Key Changes:

- Bump cardano-node to `10.7.1`, cardano-cli to `10.16.0.0`, cardano-db-sync to `13.7.0.4` and mithril to `2617.0`
- Set the default Linux kernel to `6.18` for cardano-node >= 10.7.0 LSM compatibility (avoids large IOWAIT)
- Update ZFS to `2.4` and apply a nixpkgs overlay in the AMI module for kernel 6.18 compatibility
- Fix the ZFS ARC max null check in the AMI module
- Add `extraJournalReceivers` option to the Grafana Alloy nixosModule for additional loki journal forwarding targets
```

### Section 4: Breaking Changes, Recommended Updates and Action Items

This section has three subsections:

#### Breaking

List breaking changes. If none: "None"

When there are breaking changes, explain what changed and what the user needs to do. Include code blocks for commands if relevant.

#### Recommended Updates

Always includes:
- "Update your cardano-parts pin to release version `v<date>`."
- "Complete the Action Items below."

#### Action Items

Starts with instructions on how to diff/patch template files:

```
Diff and patch the following files with `just template-diff "$FILE"` and then `just template-patch "$FILE"`. Looking at the short PR diff for these files found at directory `templates/cardano-parts-project/` prior to diffing and patching against your own repo can also be helpful.

Alternatively, if you know you would just like to mirror any of these template files without diffing or patching, use the `just template-clone "$FILE"` recipe.
```

Then a list of template files that were modified, with aligned inline comments. Use a code block:

```
Justfile                                                                    # For leios support, nix-copy/pin recipes
flake/colmena.nix                                                          # For hasCardanoParts guard, removed staticIpv6
flake/nixosModules/ami.nix                                                  # For kernel 6.18, ZFS 2.4 overlay, ARC max fix
flake/opentofu/cluster.nix                                                  # For IMDSv2 enforcement, IPv6 bootstrap fix
flake/opentofu/grafana/dashboards/cardano-node.json                         # For restructured rows, mempool timeout panels
```

Mark new files with `(New: ...)` and deleted files with `(Delete: ...)` in the comment.

After the template file list, add an "Additionally:" section for any extra steps like running tofu commands:

```
Additionally:

- Execute `just cf terraformState` to apply the updated bucket policy
- Rebuild AMIs with `just tofu bootstrap plan` and `just tofu bootstrap apply`
- Execute `just tofu apply` to update EC2 settings
- Execute `just tofu grafana apply` to update dashboards
```

### Section 5: Known Issues

List any known issues with numbered items. If none: "N/A"

Example:
```
### Known Issues:

1. Two escape chars missed in `update-ips` just recipe—add two extra `\` characters as shown in this commit diff fix
2. The `boot.zfs.zfsArcPct` option introduced a bug where zfs_arc_cache kernel cmdline param can be set to null in edge case preventing AMI boot. Fixed in next release; patch available in linked commit.
```

## Determining Versions

To find current versions, check the flake inputs and package definitions. Key files:

- `flake.nix` — flake inputs with version pins
- `flake.lock` — locked versions
- `flake/*/pkgs.nix` or similar — package version references

Compare against the previous release PR to determine which versions changed (and thus should be bolded).

## Determining Template Files

Template files live under `templates/cardano-parts-project/`. Any file in that directory that was modified on this branch should appear in the action items list. Run:

```bash
git diff --name-only main..HEAD -- templates/cardano-parts-project/
```

Strip the `templates/cardano-parts-project/` prefix in the action items list — show only the path relative to the downstream project root.
