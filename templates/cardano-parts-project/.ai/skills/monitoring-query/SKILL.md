---
name: monitoring-query
description: Query a cardano-parts cluster's Grafana Loki (logs) and Mimir (metrics) datasources directly via the Grafana datasource-proxy API for cluster log/metric analysis. Use when investigating node behavior, cardano network forks, log events, or metrics on a monitored environment instead of asking the user for manual Grafana exports.
---

# Querying cardano-parts monitoring (Loki logs + Mimir metrics) from the CLI

This skill is deployment-agnostic: it ships with the cardano-parts template and works against any
cardano-parts cluster that exposes a Grafana with Loki + Mimir datasources. The only per-deployment
values are the Grafana URL and the service-account secret path — both are **discovered from the
repo**, not hard-coded here (see Access). Everything else (query shapes, label schema, cardano-node
metric/trace names, parsing) is common across cardano-parts deployments.

## Access

Two per-deployment values; resolve them once at the start of a session, then reuse `$GRAFANA_URL`
and `$TOKEN` in every example below.

- **Grafana base URL** — per deployment. The source of truth is this repo's MCP launcher
  `scripts/ai/grafana-mcp` (its `GRAFANA_URL` default). Resolve it, honoring an env override:

  ```sh
  GRAFANA_URL="${GRAFANA_URL:-$(sed -n 's#.*GRAFANA_URL:-\([^}]*\)}.*#\1#p' scripts/ai/grafana-mcp)}"
  ```

  If the launcher isn't present, set `GRAFANA_URL` yourself or ask the SRE for the cluster's
  monitoring URL.
- **Auth** — a Grafana service-account token (Viewer role), sent as `Authorization: Bearer <token>`.
  By cardano-parts convention it is sops-age encrypted in this repo under `secrets/ai/`
  (default `secrets/ai/monitoring-service-account`, overridable via `MONITORING_SA_SECRET`).
  Decrypt with the agent age identity — **never print the token**:

  ```sh
  SECRET="${MONITORING_SA_SECRET:-secrets/ai/monitoring-service-account}"
  TOKEN=$(SOPS_AGE_KEY_FILE=~/.age-ai/credentials nix shell nixpkgs#sops -c sops -d "$SECRET")
  ```

  Other agent secrets live in the same `secrets/ai/` directory.
- No tunnel needed: token auth bypasses the Google OAuth2 login path.
- Datasource UIDs (list with `GET $GRAFANA_URL/api/datasources`): typically `loki` (Loki),
  `mimir` (Prometheus/Mimir), `alertmanager_mimir`. Confirm per deployment — UIDs can differ.

## Structured alternative: the Grafana MCP

A Grafana MCP server (`grafana/mcp-grafana`) is available for structured queries instead of raw curl —
tools like `query_loki_logs`, `query_prometheus`, `list_datasources`, `search_dashboards`,
`get_panel_image`, plus alerts/incidents/oncall. It authenticates with the same Viewer
service-account token (read-only — write tools are denied). Timestamps without an offset are UTC.

Register once per user (tools load on next session start):

```sh
just ai-grafana-mcp               # registers this repo's launcher with Claude Code (user scope)
claude mcp get grafana            # expect: ✔ Connected ;  remove: claude mcp remove grafana -s user
```

The launcher `scripts/ai/grafana-mcp` decrypts the token from sops at launch (`SOPS_AGE_KEY_FILE`,
default `~/.age-ai/credentials`) and runs `nix run nixpkgs#mcp-grafana` over stdio — no secret stored
in the MCP config. Both the launcher and the `ai-grafana-mcp` recipe ship with the cardano-parts
template, so every SRE on a given cluster gets the same setup without per-workstation config. The
launcher carries this deployment's `GRAFANA_URL` / `MONITORING_SA_SECRET` defaults; override them in
the environment to point at a different Grafana. The curl recipes below still apply (they cover the
raw datasource-proxy queries and work without the MCP).

## Loki query pattern

```sh
URL="$GRAFANA_URL/api/datasources/proxy/uid/loki/loki/api/v1/query_range"
START=$(date -u -d '2026-06-11T03:27:00Z' +%s)000000000   # nanosecond epoch
END=$(date -u -d '2026-06-11T03:28:40Z' +%s)000000000
curl -sfG -H "Authorization: Bearer $TOKEN" "$URL" \
  --data-urlencode 'query={environment="<env>", systemd_unit="cardano-node.service", instance=~"<env>.-(bp|rel).*"} |~ "AddedToCurrentChain|SwitchedToAFork"' \
  --data-urlencode "start=$START" --data-urlencode "end=$END" \
  --data-urlencode "limit=2000" --data-urlencode "direction=forward"
```

Replace `<env>` with one of this cluster's `environment` values (discover them — see Label schema).

## Log formats: JSON vs human-readable — detect before parsing

Node log format is a per-host tracer-config choice (`Stdout MachineFormat` = JSON vs
`Stdout HumanFormat*` = text) and **may change at any redeploy**. Some environments emit JSON,
most are human-readable, and it varies per cluster. Never assume — sample one line first:

```sh
... | jq -r '.data.result[0].values[0][1]' | head -c 120
# starts with '{' → JSON (MachineFormat); otherwise human-readable
```

Loki **line filters** (`|=`, `|~`, `!=`) are plain substring/regex and work identically on both
formats — namespaces, trace kinds, hashes, and hostnames appear in the text either way, so the
query side of this skill is format-agnostic. Only the *extraction* step differs.

Unpack — JSON-format hosts (each value is `[ts, logline]`, logline is a JSON object):

```sh
... | jq -r '[.data.result[].values[][1]] | .[]' \
    | jq -rc '[.at, .host, (.data.kind // .ns), ((.data.newtip // .data.block // "") | tostring | .[0:60])] | join(" | ")' \
    | sort -u
```

Unpack — human-readable hosts. Verified shape (HumanFormatColoured, note leading ANSI color
escapes): `ESC[34m[timestamp][host:Namespace.Path](Severity,thread)ESC[0m message…`

```sh
... | jq -r '[.data.result[].values[][1]] | .[]' \
    | sed -E $'s/\x1b\\[[0-9;]*m//g; s/^\\[([^]]+)\\]\\[([^:]+):([^]]+)\\]\\(([^,]+),[0-9]+\\) /\\1 | \\2 | \\3 | \\4 | /' \
    | sort -u
# → "2026-06-12 17:47:35.0075Z | <host> | ChainDB.AddBlockEvent.AddedToCurrentChain | Notice | Chain extended, new tip: …"
```

(Always strip ANSI first — the color codes otherwise break anchored regexes and column tools.)

For mixed-format result sets (cross-environment queries), split on the leading `{` and run each
half through its parser, or fall back to grep-level analysis (counts, timestamps, hash
occurrences) which needs no parsing at all. If a recipe that worked before suddenly returns
nothing through `jq`, re-check the format — it may have changed under you.

Run `jq` via `nix shell nixpkgs#jq -c sh -c '...'` if not on PATH. Always `sort` output: Loki returns
per-stream batches, not globally time-ordered lines. Pipe long output to a file first and post-filter, rather than re-querying.

## Label schema (cardano-parts clusters)

cardano-parts deployments share this label structure; the concrete **values** are per-cluster —
always discover them rather than assuming.

- `environment` — cluster/network name; discover current values via
  `GET $GRAFANA_URL/api/datasources/proxy/uid/loki/loki/api/v1/label/environment/values`.
  (Illustrative snapshot from one deployment: `buildkite, dijkstra, leios, mainnet, misc, preprod,
  preview, sanchonet` — do **not** trust this list; query yours.)
- `instance` — host, pattern `<env><group>-<role>-<az>-<n>` (e.g. `leios2-bp-b-1`, `preprod2-rel-a-1`).
- `group` — e.g. `leios1`, `preprod2`.
- `systemd_unit` — e.g. `cardano-node.service`.
- `syslog_identifier` — e.g. `cardano-node-start`.

## Useful line filters for cardano-node (new tracing system)

- Chain selection: `|~ "AddedToCurrentChain|SwitchedToAFork|TrySwitchToAFork|IgnoreBlock"`
- Forging: `|~ "TraceNodeIsLeader|TraceForgedBlock|TraceAdoptedBlock"`
- Leios (if the deployment runs it): `|~ "LeiosBlockForged|LeiosBlockStored|LeiosBlockAcquired|LeiosBlockPointMissing|LeiosVoted|LeiosVoteAcquired"`
- Track one block: `|= "<hash-prefix>"` across `{environment="<env>"}` with NO instance filter
  (other services — dbsync, centrifuge, faucet hosts — also run nodes and see blocks).
- Exclude noise: `!= "StateQueryServer" != "RequestNext" != "StartLeadershipCheck"`

Caveat: at typical default severities there are NO `ChainSync.*` / `BlockFetch.*` traces —
block transfer is only observable indirectly via `ChainDB.AddBlockEvent.*` on the receiver and
`Forge.*` on the producer. Absence of a hash in logs ≠ absence of transfer attempts. (Severity
config is per-deployment — confirm what your cluster emits.)

## Mimir (metrics) query pattern

```sh
curl -sfG -H "Authorization: Bearer $TOKEN" \
  "$GRAFANA_URL/api/datasources/proxy/uid/mimir/api/v1/query_range" \
  --data-urlencode 'query=cardano_node_metrics_blockNum_int{environment="<env>"}' \
  --data-urlencode "start=$(date -u -d '...' +%s)" --data-urlencode "end=$(date -u -d '...' +%s)" \
  --data-urlencode "step=15"
```

Mimir start/end are SECONDS (not ns). Metrics scrape interval is commonly 1 minute — use `step=60`;
treat ±1-sample skew across hosts as scrape jitter (confirm the scrape interval per deployment).

Discover the full metric scope per host (~400 series) via:
`.../api/v1/series --data-urlencode 'match[]={__name__=~".+", instance="<host>"}'` (plus start/end).

Key cardano-node metric names (new tracing system, `cardano_node_metrics_` prefix):
- `blockNum_int`, `slotNum_int`, `density_real` — chain tip per instance; pivot per-host over time
  to map forks/stalls/islands.
- `blockfetchclient_blockdelay_real` — delay of the LAST completed block fetch; if it freezes at a
  constant while others move, that node's BlockFetch client is wedged (smoking gun for one-way
  protocol stalls). Also `blockfetchclient_lateblocks_counter`, `_blocksize_int`.
- `ChainSync_HeadersServed_counter`, `served_header_counter`, `served_block_counter` — server-side
  serving activity (proves the other direction of a connection is alive).
- `peerSelection_Hot_int` / `_Warm_int` / `_Cold_int` (+ `*Promotions/Demotions`) — peer state machine.
- `connectionManager_*`, `Forge_*` (incl. Leios `Forge_endorser_block_*`), `Mempool_*`, `blockperf_*`.

## Gotchas

- Loki caps `limit` (5000); narrow the time window or add filters rather than paginating blindly.
- `direction=forward` for chronological investigation.
- Slot-to-wallclock: derive the offset and slot length from config (or any log line that has both
  slot + timestamp, e.g. `Forge.Loop.StartLeadershipCheck`). Devnets often run 1 slot = 1 s;
  mainnet/testnets use the network's `slotLength` — don't assume.
- Grafana-UI JSON exports wrap lines as `[{line: "<json-string>", ...}]` — prefer direct API queries.
