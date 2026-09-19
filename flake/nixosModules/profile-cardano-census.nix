# nixosModule: profile-cardano-census
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-census.asnDatabase.enable
#   config.services.cardano-census.asnDatabase.maxAgeHours
#   config.services.cardano-census.asnDatabase.minRelays
#   config.services.cardano-census.asnDatabase.url
#   config.services.cardano-census.extraArgs
#   config.services.cardano-census.forkTolerance
#   config.services.cardano-census.interval
#   config.services.cardano-census.labels
#   config.services.cardano-census.package
#   config.services.cardano-census.parallel
#   config.services.cardano-census.poolIndex
#   config.services.cardano-census.reportFile
#   config.services.cardano-census.timeout
#   config.services.cardano-census.topPools
#
# Tips:
#   * This is a cardano-parts add-on to the upstream cardano-census nixos module, which it imports
#   * Probes every big ledger peer relay the local cardano-node knows and publishes what answered, by stake
#   * Publishes cardano-census.prom into the alloy textfile-collector directory
#   * On a host with profile-cardano-db-sync it also names pools from db-sync, so the
#     outreach series carry pool id, ticker and name
#   * Requires profile-grafana-alloy (auto-sets textfileCollectorDirectory
#     to "/var/lib/node-textfile" via mkDefault when the consumer doesn't
#     override it)
#   * Requires profile-cardano-node-group (auto-sets shareNodeSocket = true)
#   * Import on one or two hosts per environment; every host publishes a full copy of the series
#
# # README
# ## Big ledger peer reachability census
#
# The `profile-cardano-census` NixOS profile runs
# [cardano-census](https://github.com/input-output-hk/cardano-census) from a
# systemd timer. Each run asks the local cardano-node for its big ledger peer
# snapshot over the node socket, probes every relay in it with one
# node-to-node handshake and chainsync tip request, and publishes what
# answered as `cardano_census_*` series: reachable stake, reachability by
# time, chain agreement, SRV record health, and failures by autonomous
# system. The upstream README documents every series.
#
# ### Enabling
#
# Import `profile-cardano-census` alongside `profile-grafana-alloy` and
# `profile-cardano-node-group`:
#
#     {
#       imports = [
#         flake.config.flake.nixosModules.profile-cardano-node-group
#         flake.config.flake.nixosModules.profile-grafana-alloy
#         flake.config.flake.nixosModules.profile-cardano-census
#       ];
#     }
#
# Importing is enough. The profile points census at this node's socket and
# network magic, stamps every series with `environment` and `group` since the
# node exporter path adds only `instance` and `job`, writes into the alloy
# textfile directory, and sets
# `services.alloy.textfileCollectorDirectory` to `"/var/lib/node-textfile"`
# via `mkDefault` and `services.cardano-node.shareNodeSocket = true`.
# Upstream options remain available under `services.cardano-census` for
# tuning, for example `interval`, `timeout` and `asnDatabase.enable`.
#
# ### Where to run it
#
# The census measures the network from wherever it runs, so one host per
# environment gives the picture and a second in another region shows what
# differs by vantage point. Every additional host publishes a complete copy
# of the series differing only by `instance`, roughly 400 series with the
# autonomous system breakdown, so avoid importing it on a whole group.
#
# ### Naming pools from db-sync
#
# The peer snapshot names no pools. On a host that also imports
# `profile-cardano-db-sync`, the profile runs a `psql` query before each
# census that writes the latest registration of every pool, its relays,
# bech32 id, ticker and name, to `/var/lib/cardano-census/pool-index.json`,
# and passes it as `services.cardano-census.poolIndex`. Access is by the
# local socket ident map: the census unit's dynamic user is added to
# `services.cardano-db-sync.additionalDbUsers`. The
# `cardano_census_pool_stake_ratio` series then carries `pool_id`, `ticker`
# and `name` for the largest unreachable operators, which is what makes the
# dashboard's outreach table actionable. Hosts without db-sync get the same
# series named by first relay address.
#
# ### Cadence and duration
#
# A run probes every relay with a 60 second budget, so mainnet takes one to
# two minutes and the default 15 minute interval leaves ample room. The
# autonomous system database is fetched from iptoasn.com by an
# `ExecStartPre` when the local copy is older than a day; a failed fetch
# keeps the previous copy and the census runs regardless. Set
# `services.cardano-census.asnDatabase.enable = false` on hosts without
# outbound HTTPS.
{inputs, ...}: {
  flake.nixosModules.profile-cardano-census = {
    config,
    lib,
    options,
    pkgs,
    ...
  }:
    with builtins;
    with lib; let
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (groupCfg.meta) environmentName;
      inherit (cardanoLib.environments.${environmentName}.${nodeConfigGenesis}) ByronGenesisFile;
      inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;

      groupCfg = config.cardano-parts.cluster.group;
      perNodeCfg = config.cardano-parts.perNode;
      cfgNode = config.services.cardano-node;

      # Remove this usage once legacy tracing is dropped from node
      nodeConfigGenesis =
        if cardanoLib.environments.${environmentName} ? nodeConfig
        then "nodeConfig"
        else "nodeConfigLegacy";

      # Detect whether profile-grafana-alloy is co-imported by probing
      # for an option it declares.  Using `options` (declarations) rather
      # than `config` (values) avoids circular-evaluation surprises.
      alloyImported = options ? services && options.services ? alloy;

      # On a db-sync host the census can name pools: the same ledger
      # registrations the snapshot is built from sit in pool_relay, with the
      # bech32 id in pool_hash.view and the ticker in off_chain_pool_data.
      # Presence is decided from `options` so the fragment's existence never
      # depends on `config`; whether it applies is a mkIf on the enable flag.
      dbSyncImported = options ? services && options.services ? cardano-db-sync;
      poolIndexFile = "/var/lib/cardano-census/pool-index.json";
      buildPoolIndex = pkgs.writeShellScript "cardano-census-pool-index" ''
        set -euo pipefail
        out="$STATE_DIRECTORY/pool-index.json"
        ${config.services.postgresql.package}/bin/psql -X -At -v ON_ERROR_STOP=1 -U cexplorer -d cexplorer > "$out.tmp" <<'SQL'
          WITH latest AS (
            SELECT DISTINCT ON (hash_id) id AS update_id, hash_id, meta_id
            FROM pool_update
            ORDER BY hash_id, registered_tx_id DESC, id DESC
          ),
          relays AS (
            SELECT l.hash_id,
                   json_agg(
                     COALESCE(pr.dns_name, pr.ipv4, '[' || pr.ipv6 || ']', pr.dns_srv_name)
                     || CASE WHEN pr.port IS NULL OR pr.dns_srv_name IS NOT NULL THEN ''' ELSE ':' || pr.port END
                   ) AS relays
            FROM latest l
            JOIN pool_relay pr ON pr.update_id = l.update_id
            GROUP BY l.hash_id
          )
          SELECT COALESCE(json_agg(json_build_object(
                   'pool_id', ph.view,
                   'ticker', m.ticker_name,
                   'name', m.json->>'name',
                   'relays', r.relays)), '[]'::json)
          FROM relays r
          JOIN pool_hash ph ON ph.id = r.hash_id
          LEFT JOIN latest l ON l.hash_id = ph.id
          LEFT JOIN LATERAL (
            SELECT o.ticker_name, o.json
            FROM off_chain_pool_data o
            WHERE o.pool_id = ph.id
            ORDER BY (o.pmr_id = l.meta_id) DESC, o.id DESC
            LIMIT 1
          ) m ON true;
        SQL
        [ -s "$out.tmp" ] || echo '[]' > "$out.tmp"
        mv "$out.tmp" "$out"
      '';

      # Read the effective textfile directory.  Our mkDefault below
      # provides "/var/lib/node-textfile" when the consumer doesn't
      # override it; when alloy isn't imported the dummy value is never
      # reached because the assertion halts the build first.
      textfileDirectory =
        if alloyImported
        then let
          val = config.services.alloy.textfileCollectorDirectory;
        in
          if val == null
          then
            throw ''
              profile-cardano-census requires
              services.alloy.textfileCollectorDirectory to be non-null.
              The profile defaults it to "/var/lib/node-textfile" via
              mkDefault; if you override it to null, pick a real path.
            ''
          else val
        else "/var/lib/node-textfile"; # dummy; assertion fires first
    in {
      key = ./profile-cardano-census.nix;

      imports = [inputs.cardano-census.nixosModules.default];

      config = mkMerge ([
          {
            # Self-enable: importing the profile is sufficient.
            services.cardano-node.shareNodeSocket = true;

            assertions = [
              {
                assertion = alloyImported;
                message = ''
                  profile-cardano-census requires
                  profile-grafana-alloy to be imported on this host.
                  Import profile-grafana-alloy (optionally override
                  services.alloy.textfileCollectorDirectory, which
                  defaults to "/var/lib/node-textfile").
                '';
              }
            ];

            services.cardano-census = {
              enable = true;
              nodeSocket = cfgNode.socketPath 0;
              networkMagic = protocolMagic;
              nodeSocketGroup = "cardano-node";
              inherit textfileDirectory;

              # The node exporter path through alloy adds instance and job
              # only; environment and group are stamped by the census itself,
              # as profile-cardano-committee-monitor's collector does.
              labels = {
                environment = environmentName;
                group = groupCfg.groupName;
              };
            };

            systemd.services.cardano-census = {
              # Soft Wants= (not Requires=) so the timer still fires if
              # cardano-node is wedged; the run then fails at the socket and
              # writes cardano_census_success 0 rather than going stale.
              after = ["cardano-node.service" "cardano-node-socket-share.service"];
              wants = ["cardano-node.service"];

              # The textfile directory is setgid node-textfile, owned by the
              # alloy profile; the upstream module already joins cardano-node.
              serviceConfig.SupplementaryGroups = ["node-textfile"];
            };
          }
        ]
        # Only set alloy options when the module is present; when absent
        # these option paths don't exist and including them (even under
        # mkIf false) would be an eval error.  `optional false …` yields
        # [], so the attrset never enters mkMerge.
        ++ optional alloyImported {
          services.alloy.textfileCollectorDirectory = mkDefault "/var/lib/node-textfile";
          services.alloy.extraPrometheusRelabelNodeKeepRegex = ["^cardano_census_.*$"];
        }
        # With db-sync on the host, build the pool index before each run.
        # The census unit's DynamicUser is named after the unit, so listing
        # it in additionalDbUsers maps it to the cexplorer role over the
        # local socket; a failed build keeps the previous index.
        ++ optional dbSyncImported (mkIf config.services.cardano-db-sync.enable {
          services.cardano-db-sync.additionalDbUsers = ["cardano-census"];
          services.cardano-census.poolIndex = poolIndexFile;
          systemd.services.cardano-census = {
            after = ["postgresql.service"];
            serviceConfig = {
              ExecStartPre = ["-${buildPoolIndex}"];
              ReadWritePaths = ["/run/postgresql"];
            };
          };
        }));
    };
}
