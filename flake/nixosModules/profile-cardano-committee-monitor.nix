# nixosModule: profile-cardano-committee-monitor
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-committee-monitor.enable
#
# Tips:
#   * Periodic collector for cardano constitutional-committee state metrics
#   * Publishes a .prom file into the alloy textfile-collector directory
#   * Requires profile-grafana-alloy with services.alloy.textfileCollectorDirectory set
#   * Requires profile-cardano-node-group and services.cardano-node.shareNodeSocket = true
#   * Import on exactly one host per environment to avoid duplicate alerts
#   * Cadence is paired with cardano_cc_metrics_stale in cardano-committee.nix-import
{
  flake.nixosModules.profile-cardano-committee-monitor = {
    config,
    pkgs,
    lib,
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
      cfg = config.services.cardano-committee-monitor;
      secondsPerEpoch = epochLength * slotLength;
      collect = pkgs.callPackage ../../flakeModules/lib/cardano-committee-monitor-collect.nix {inherit cardano-cli;};

      # attrByPath rather than a direct attr access: a direct
      # `config.services.alloy.textfileCollectorDirectory` would throw at
      # eval time when profile-grafana-alloy isn't imported, before any
      # friendlier error can surface.
      textfileDirectory = attrByPath ["services" "alloy" "textfileCollectorDirectory"] null config;

      # NixOS assertions only fire AFTER full config eval, so an eager
      # `"${null}/…"` interpolation in the unit body would throw "cannot
      # coerce null to string" first and hide the assertion message. The
      # throw lives in a let-binding so it's deferred until first use,
      # which only happens inside `mkIf cfg.enable`.
      textfileDirectoryOrThrow =
        if textfileDirectory == null
        then
          throw ''
            profile-cardano-committee-monitor requires
            services.alloy.textfileCollectorDirectory to be non-null.
            Import profile-grafana-alloy on this host and set the
            option to a directory path (e.g. "/var/lib/node-textfile").
          ''
        else textfileDirectory;
    in {
      key = ./profile-cardano-committee-monitor.nix;

      options.services.cardano-committee-monitor = {
        enable = mkEnableOption "Cardano constitutional-committee state metrics collector";
      };

      config = mkIf cfg.enable {
        services.alloy.extraPrometheusRelabelNodeKeepRegex = ["^cardano_cc_.*$"];

        # No assertion on services.cardano-node.enable: the `inherit
        # (config.environment.variables) CARDANO_NODE_*` below is eager
        # and throws first, leaving any such assertion dead.
        # profile-cardano-node-group is documented (not asserted).
        assertions = [
          {
            assertion = config.services.cardano-node.shareNodeSocket;
            message = ''
              profile-cardano-committee-monitor requires
              services.cardano-node.shareNodeSocket = true so the
              collector can read the cardano-node socket via its
              supplementary group.
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
            OUT = "${textfileDirectoryOrThrow}/cardano-committee.prom";
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
            ReadWritePaths = [textfileDirectoryOrThrow];
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
      };
    };
}
