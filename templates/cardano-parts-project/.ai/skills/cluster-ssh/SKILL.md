---
name: cluster-ssh
description: SSH into a cardano-parts cluster's hosts over shared ControlMaster sockets to run read-only on-host diagnostics (journalctl, systemctl, zfs, cardano db tools, etc.), and move bulk state directly between hosts with wush when needed. Use when investigating node or host behavior directly on the machine — when telemetry (see the monitoring-query skill) isn't enough, or you need to inspect units, files, or local state. Requires an SRE to have opened the masters first.
---

# On-host access to cardano-parts cluster machines

This skill ships with the cardano-parts template and is deployment-agnostic: the mechanism (the
`ai-ssh` recipes, ControlMaster sockets, `nss_wrapper`) is identical across cardano-parts clusters.
Only the host names differ — discover them per cluster (see §3). Example hostnames below are
illustrative.

Cluster hosts are reached through **AWS SSM** (`ProxyCommand … aws ssm start-session …`), so an
agent sandbox — which usually has no AWS creds and no outbound AWS network — **cannot dial hosts
itself**. Instead, an SRE opens persistent SSH **ControlMaster** sessions, and the agent rides the
shared sockets. The agent never needs AWS creds: the master process holds the SSM tunnel.

This is the escalation path from the `monitoring-query` skill: use telemetry first; come here when
you need to read units/files/DB state on the box. **Default to read-only commands** (`journalctl`,
`systemctl status`, `zfs list`, `jq`, `cat`, `ls`, `db-analyser --help`). Anything that mutates
state (restart, edit, destroy, write) MUST be confirmed with the SRE first.

## 1. SRE opens the masters (their side)

From the repo root the SRE runs the `just ai-ssh` recipe with the host(s) to expose:

```sh
just ai-ssh <host> [<host> ...]      # e.g. just ai-ssh group1-role-a-1
just ai-ssh-list                     # show which masters are live
just ai-ssh-close [<host> ...]       # close all, or the named hosts
```

`ai-ssh` (re)generates an agent ssh config and opens a backgrounded master per host. It prints the
two paths the agent needs:

- **Agent config:** `$AI_SSH_DIR/ssh_config_ai`
- **Socket dir:** `$AI_SSH_DIR` (sockets named `cm-<hostname>`)

`AI_SSH_DIR` defaults to a repo-local `.ssh-ai/` but the SRE may set it to a path your sandbox can
read (e.g. a mounted share). **Don't assume a path — use the one the recipe printed**, or ask the
SRE for `AI_SSH_DIR`. The config embeds an absolute `ControlPath`, so it resolves to the same socket
from your sandbox despite a different `$HOME`/cwd.

## 2. Agent rides the masters (your side)

Connect with the generated config; the master does the I/O, so no creds/tunnel are needed:

```sh
CFG="$AI_SSH_DIR/ssh_config_ai"          # the path the recipe printed
ssh -F "$CFG" <host> '<read-only command>'
```

**Always verify the master is up first** (non-dialing — fails fast if the SRE hasn't opened it):

```sh
ssh -F "$CFG" -O check <host>            # "Master running (pid=…)" = good
```

### If your sandbox is unprivileged with no passwd entry

OpenSSH aborts with `No user exists for uid …` when the sandbox uid isn't in `/etc/passwd`. Fix with
`nss_wrapper` (a fake passwd/group + `LD_PRELOAD`). One-time bootstrap, then wrap every ssh call:

```sh
NW=$(nix build --no-link --print-out-paths nixpkgs#nss_wrapper)
printf 'agent:x:%s:%s::%s:/bin/sh\n' "$(id -u)" "$(id -g)" "$HOME" > /tmp/nwpasswd
printf 'agent:x:%s:\n' "$(id -g)" > /tmp/nwgroup

# /tmp/sshw — invoke as:  bash /tmp/sshw <host> '<cmd>'
cat > /tmp/sshw <<EOF
#!/usr/bin/env bash
exec env LD_PRELOAD="$NW/lib/libnss_wrapper.so" \\
  NSS_WRAPPER_PASSWD=/tmp/nwpasswd NSS_WRAPPER_GROUP=/tmp/nwgroup \\
  USER=agent LOGNAME=agent ssh -F "$CFG" "\$@"
EOF
bash /tmp/sshw <host> -O check          # verify, then run real commands
```

If your sandbox already has a passwd entry, skip the wrapper and use `ssh -F "$CFG"` directly.

## 3. Finding hosts

```sh
just ssh-list name '.*'                  # all node names
just ssh-list name 'preprod.*'           # filtered
nix eval --json '.#nixosConfigurations' --apply builtins.attrNames | jq
```

Naming: `<env><n>-<role>-<az>-1`, e.g. `leios1-rel-a-1`, `preprod2-bp-b-1`. Block producers
(`-bp-`) sit behind their relays (`-rel-`); an SRE may only have opened a subset — check
`just ai-ssh-list`.

## Moving bulk data between hosts (`wush`)

The agent reaches hosts only through the SRE's SSM/ControlMaster path, and cluster hosts generally
**cannot SSH to each other directly** (SSM-only; inter-host port 22 is typically closed). So relaying a
large file host→agent→host is slow and fragile — it crosses the SSM tunnel twice and dies if a master
flaps. When you need to move bulk state between two machines — e.g. transplanting a node's database /
state directory from a healthy donor onto a broken one — use **`wush`** if it's installed
(`command -v wush`; on NixOS it can be added to system packages or fetched via `nix`).

`wush` is a WireGuard-powered peer-to-peer transfer + shell tool. It stands up its own encrypted
overlay between the two hosts (direct UDP, or DERP-relayed when there's no direct path), so bytes flow
**host-to-host**, bypassing both the SSM bottleneck and the missing inter-host SSH — typically orders
of magnitude faster than relaying through the agent.

**Model:** one side runs `wush serve` (it prints an `--auth-key`); the other runs a client
(`wush rsync`, `wush cp`, `wush ssh`, `wush port-forward`) with that key. A leading `:` denotes a path
on the *server*:

```sh
# On the SERVER host (the one you transfer to/from). Run it backgrounded; it prints the auth key
# on the line just after "Picked DERP region …".
wush serve                                                    # → auth key: <base58 string>

# On the CLIENT host, with that key (extra rsync flags go after `--`):
wush rsync --auth-key <key> :/srv/path  /local/path  -- -a    # pull  (server → client)
wush rsync --auth-key <key> /local/path :/srv/path   -- -a    # push  (client → server)
```

Driving it from the agent: start `wush serve` on one host as a backgrounded SSM session, read its auth
key from the output, then run the `wush rsync` client on the other host. One running serve + key
handles multiple parallel clients, so a single donor can fan its data out to several recipients at once.

**Transplanting live state safely:**
- Briefly **stop the service on the source** for an on-disk-consistent copy, then restart — NEVER copy
  a database that's being written. To shorten the source's downtime, stage a scratch copy while it's
  stopped and serve the transfer from that. A plain `cp` of the state dir *may* be near-instant on ZFS
  (a `copy_file_range` block-clone) — but only with OpenZFS ≥ 2.2, the `block_cloning` pool feature,
  `zfs_bclone_enabled=1`, and a `cp` that does reflinks (GNU coreutils ≥ 9); otherwise it's a full
  copy. Don't assume it — check (`zpool get feature@block_cloning`, `cat
  /sys/module/zfs/parameters/zfs_bclone_enabled`), or just keep the source stopped for the whole
  transfer. For a guaranteed-instant *and* consistent point-in-time source, `zfs snapshot` works
  regardless of `cp` behavior — but remember to `zfs destroy` it afterward.
- `rsync -a` preserves owner/perms; cluster hosts share the same service uid/gid, so ownership comes
  across correctly. State dirs carry no per-host identity (keys live elsewhere), so they're safe to
  clone between same-network nodes.
- This **mutates the target** — confirm with the SRE first; read-only-by-default still applies.
- **Cleanup:** stop the server with **`pkill -x wush`** — *not* `pkill -f "wush serve"`, which also
  matches your own command line and kills your shell. Remove any scratch copies you staged.

## Norms & gotchas

- **Read-only by default.** Surface anything mutating to the SRE before running it.
- **Hosts are UTC** — no `--utc` needed for `journalctl -S/-U`.
- **journald JSON lines are duplicated (×2)** in some setups — sanity-check counts.
- **Capture long output to a file, then grep/parse it** — don't re-run expensive `journalctl`/`curl`.
- Node log format (JSON vs human) is a per-host tracer choice and can change on redeploy — sample a
  line before parsing (same caveat as the `monitoring-query` skill).
- Masters expire after `AI_SSH_PERSIST` (default 2h); if `-O check` fails, ask the SRE to re-run
  `just ai-ssh <host>`.
- **Don't relay bulk data through your sandbox** — to move large state between hosts use `wush`
  (see *Moving bulk data between hosts*), which goes host-to-host and survives master flaps.
