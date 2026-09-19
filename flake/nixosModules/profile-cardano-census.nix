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
#   config.services.cardano-census.reportFile
#   config.services.cardano-census.timeout
#
# Tips:
#   * This is a cardano-parts add-on to the upstream cardano-census nixos module, which it imports
#   * Probes every big ledger peer relay the local cardano-node knows and publishes what answered, by stake
#   * Publishes cardano-census.prom into the alloy textfile-collector directory
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
        });
    };
}
