# nixosModule: profile-cardano-committee-monitor
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#   * Periodic collector for cardano constitutional-committee state metrics
#   * Publishes a .prom file into the alloy textfile-collector directory
#   * Requires profile-grafana-alloy (auto-sets textfileCollectorDirectory
#     to "/var/lib/node-textfile" via mkDefault when the consumer doesn't
#     override it)
#   * Requires profile-cardano-node-group (auto-sets shareNodeSocket = true)
#   * Import on exactly one host per environment to avoid duplicate alerts
#   * Cadence is paired with cardano_cc_metrics_stale in cardano-committee.nix-import
#
# # README
# ## Constitutional-committee state monitoring
#
# The `profile-cardano-committee-monitor` NixOS profile publishes Prometheus
# metrics about the on-chain constitutional-committee state (per-member term
# expiration, hot-key authorisation status, next-epoch-change signal). The
# metric series are prefixed `cardano_cc_*`. Alerts that consume them live in
# [./flake/opentofu/grafana/alerts/cardano-committee.nix-import](./flake/opentofu/grafana/alerts/cardano-committee.nix-import)
# and are deployed via `just tofu grafana apply` like the rest of the
# monitoring stack.
#
# ### Enabling
#
# Import `profile-cardano-committee-monitor` on exactly **one** host per
# environment, alongside `profile-grafana-alloy` and
# `profile-cardano-node-group`:
#
#     {
#       imports = [
#         flake.config.flake.nixosModules.profile-cardano-node-group
#         flake.config.flake.nixosModules.profile-grafana-alloy
#         flake.config.flake.nixosModules.profile-cardano-committee-monitor
#       ];
#     }
#
# The profile auto-sets `services.alloy.textfileCollectorDirectory` to
# `"/var/lib/node-textfile"` via `mkDefault` and
# `services.cardano-node.shareNodeSocket = true`.  Override the directory
# with a normal assignment if you need a different path.
#
# The profile asserts that `profile-grafana-alloy` is imported and that
# `services.alloy.textfileCollectorDirectory` is non-null.
# `profile-cardano-node-group` is required but not asserted — without it,
# the unit's `inherit (config.environment.variables) CARDANO_NODE_*` throws
# a native Nix evaluation error before any assertion can fire.
#
# ### One host per environment
#
# Importing the profile on more than one host per environment produces
# duplicate Prometheus series differing only by `instance`, and every alert
# fires once per duplicate host. The current implementation does not enforce
# single-host import; it is a documented expectation.
#
# ### Tuning thresholds
#
# Alert thresholds are constants in
# [`cardano-committee.nix-import`](./flake/opentofu/grafana/alerts/cardano-committee.nix-import)
# (`warnDays`, `pageDays`). This file is part of the project template — your
# repo owns it after `init`, so edit it in place. For per-environment
# thresholds (e.g. mainnet 60d/14d while testnets stay at 30d/7d), duplicate
# the relevant rules and add an `environment=~"…"` selector on each;
# PromQL has no first-class way to express per-label thresholds.
#
# ### Cadence is hardcoded
#
# The collector runs `OnCalendar=hourly` (with `RandomizedDelaySec=600`).
# The cadence is paired with the `cardano_cc_metrics_stale` threshold of
# 5400 seconds in the alert file: any miss longer than ~90 minutes trips
# the alert. The two values live in separate Nix evaluations and cannot be
# cross-checked by assertion — if you change the cadence (e.g. via
# `lib.mkForce` on `systemd.timers.cardano-committee-monitor`), change the
# staleness threshold in the alert file in the same PR.
{
  flake.nixosModules.profile-cardano-committee-monitor = {
    config,
    pkgs,
    lib,
    options,
    ...
  }:
    with builtins;
    with lib; let
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (perNodeCfg.pkgs) cardano-cli;
      inherit (groupCfg.meta) environmentName;
      inherit (cardanoLib.environments.${environmentName}.nodeConfig) ShelleyGenesisFile;
      inherit (fromJSON (readFile ShelleyGenesisFile)) epochLength slotLength;

      groupCfg = config.cardano-parts.cluster.group;
      perNodeCfg = config.cardano-parts.perNode;
      secondsPerEpoch = epochLength * slotLength;
      collect = pkgs.callPackage ../../flakeModules/lib/cardano-committee-monitor-collect.nix {inherit cardano-cli;};

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
              profile-cardano-committee-monitor requires
              services.alloy.textfileCollectorDirectory to be non-null.
              The profile defaults it to "/var/lib/node-textfile" via
              mkDefault; if you override it to null, pick a real path.
            ''
          else val
        else "/var/lib/node-textfile"; # dummy; assertion fires first
    in {
      key = ./profile-cardano-committee-monitor.nix;

      config = mkMerge ([
          {
            # Self-enable: importing the profile is sufficient.
            services.cardano-node.shareNodeSocket = true;

            # No assertion on services.cardano-node.enable: the `inherit
            # (config.environment.variables) CARDANO_NODE_*` below is eager
            # and throws first, leaving any such assertion dead.
            # profile-cardano-node-group is documented (not asserted).
            assertions = [
              {
                assertion = alloyImported;
                message = ''
                  profile-cardano-committee-monitor requires
                  profile-grafana-alloy to be imported on this host.
                  Import profile-grafana-alloy (optionally override
                  services.alloy.textfileCollectorDirectory, which
                  defaults to "/var/lib/node-textfile").
                '';
              }
            ];

            systemd.services.cardano-committee-monitor = {
              description = "Collect cardano constitutional-committee state metrics";

              # Soft Wants= (not Requires=) so the timer still fires if
              # cardano-node is wedged, surfacing as cardano_cc_metrics_stale
              # rather than silently skipped runs.
              after = ["cardano-node.service" "cardano-node-socket-share.service"];
              wants = ["cardano-node.service"];

              environment = {
                OUT = "${textfileDirectory}/cardano-committee.prom";
                ENVIRONMENT_NAME = environmentName;
                SECONDS_PER_EPOCH = toString secondsPerEpoch;
                inherit
                  (config.environment.variables)
                  CARDANO_NODE_NETWORK_ID
                  CARDANO_NODE_SOCKET_PATH
                  ;
              };

              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${collect}/bin/cardano-committee-monitor-collect";
                DynamicUser = true;
                SupplementaryGroups = ["cardano-node" "node-textfile"];
                ReadWritePaths = [textfileDirectory];
                ProtectSystem = "strict";
                NoNewPrivileges = true;
                PrivateTmp = true;
                # cardano-cli on a backpressured node can take minutes; cap
                # so a hung run doesn't silently delay the next.
                TimeoutStartSec = "300s";
              };
            };

            systemd.timers.cardano-committee-monitor = {
              wantedBy = ["timers.target"];
              timerConfig = {
                Unit = "cardano-committee-monitor.service";
                # Paired with cardano_cc_metrics_stale (5400s) in
                # cardano-committee.nix-import. The two live in separate
                # evaluations and can't be cross-checked; change together.
                OnCalendar = "hourly";
                # Spread cardano-cli load across the first 10m of the hour
                # so synchronised redeploys don't queue queries.
                RandomizedDelaySec = "600";
              };
            };
          }
        ]
        # Only set alloy options when the module is present; when absent
        # these option paths don't exist and including them (even under
        # mkIf false) would be an eval error.  `optional false …` yields
        # [], so the attrset never enters mkMerge.
        ++ optional alloyImported {
          services.alloy.textfileCollectorDirectory = mkDefault "/var/lib/node-textfile";
          services.alloy.extraPrometheusRelabelNodeKeepRegex = ["^cardano_cc_.*$"];
        });
    };
}
