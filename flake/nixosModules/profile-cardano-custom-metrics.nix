# nixosModule: profile-cardano-custom-metrics
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module
#   * This module will acquire additional cardano relevant metrics and publish
#     them as a .prom file into the alloy node-exporter textfile-collector
#     directory
#   * Requires profile-grafana-alloy (auto-sets textfileCollectorDirectory
#     to "/var/lib/node-textfile" via mkDefault when the consumer doesn't
#     override it)
#   * The upstream cardano-node nixos service module should still be imported separately
#   * The cardano-parts profile-cardano-node-group nixosModule should still be imported separately
#   * Metrics published: cardano_node_metrics_custom_ping_latency_ms
#   * Coredump detection, previously collected here via coredumpctl and pushed
#     as a netdata statsd gauge, is now covered by the Loki log alert on
#     systemd-coredump/kernel journal lines
#     (templates/cardano-parts-project/flake/opentofu/grafana/alerts-loki/cardano-parts.nix-import);
#     netdata itself is enabled by profile-basic as a local standby collector
{
  flake.nixosModules.profile-cardano-custom-metrics = {
    config,
    pkgs,
    lib,
    options,
    ...
  }: let
    inherit (lib) mkDefault mkMerge optional;
    inherit (perNodeCfg.meta) cardanoNodePort hostAddr;
    inherit (perNodeCfg.pkgs) cardano-cli;
    inherit (groupCfg) groupName;
    inherit (groupCfg.meta) environmentName;

    groupCfg = config.cardano-parts.cluster.group;
    perNodeCfg = config.cardano-parts.perNode;

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
            profile-cardano-custom-metrics requires
            services.alloy.textfileCollectorDirectory to be non-null.
            The profile defaults it to "/var/lib/node-textfile" via
            mkDefault; if you override it to null, pick a real path.
          ''
        else val
      else "/var/lib/node-textfile"; # dummy; assertion fires first

    collect = pkgs.writeShellApplication {
      name = "cardano-custom-metrics-collect";
      runtimeInputs = [cardano-cli pkgs.coreutils pkgs.jq];
      text = ''
        set -euo pipefail
        : "''${OUT:?OUT (output .prom path) must be set}"
        TMP="$OUT.tmp"

        # Cardano-cli 11.1 replaced --host and --port with a positional
        # host:port and renamed --magic to --network-magic, so the target args
        # are selected from help output to support release and pre-release cli.
        PING_HELP=$(cardano-cli ping --help 2>&1 || true)
        if grep -q -- --host <<< "$PING_HELP"; then
          PING_ARGS=(--host=${hostAddr} --port=${toString cardanoNodePort} --magic="$TESTNET_MAGIC")
        else
          PING_ARGS=(--network-magic="$TESTNET_MAGIC" ${hostAddr}:${toString cardanoNodePort})
        fi

        CARDANO_NODE_PING_LATENCY=""
        if CARDANO_NODE_PING_OUTPUT=$(cardano-cli ping \
            --count=1 \
            --quiet \
            --json \
            "''${PING_ARGS[@]}"); then
          # Check ping output for old json struct containing `pongs` and new json struct on node >= 11.1.0 w/o `pongs`
          CARDANO_NODE_PING_LATENCY=$(
            jq -s '[ .[] | (.pongs // [.])[] | select(has("sample")) ] | (.[-1].mean // empty) * 1000' <<< "$CARDANO_NODE_PING_OUTPUT"
          )
        fi

        # `environment` and `group` are baked in here because alloy's
        # node-exporter relabel chain sets only `instance` and `job` for
        # textfile-collector samples — there is no scraper-side label source.
        #
        # On ping failure the sample is omitted rather than zeroed or left
        # stale: the series goes absent, and the file mtime still advances so
        # node_textfile_mtime_seconds staleness is not tripped.
        {
          echo "# HELP cardano_node_metrics_custom_ping_latency_ms Mean cardano-cli ping latency in milliseconds against this node's public address and port."
          echo "# TYPE cardano_node_metrics_custom_ping_latency_ms gauge"
          if [ -n "$CARDANO_NODE_PING_LATENCY" ]; then
            echo "cardano_node_metrics_custom_ping_latency_ms{environment=\"${environmentName}\",group=\"${groupName}\"} $CARDANO_NODE_PING_LATENCY"
          fi
        } > "$TMP"

        # Atomic publish via rename(2) on the same filesystem.
        mv "$TMP" "$OUT"
      '';
    };
  in {
    key = ./profile-cardano-custom-metrics.nix;

    config = mkMerge ([
        {
          assertions = [
            {
              assertion = alloyImported;
              message = ''
                profile-cardano-custom-metrics requires
                profile-grafana-alloy to be imported on this host.
                Import profile-grafana-alloy (optionally override
                services.alloy.textfileCollectorDirectory, which
                defaults to "/var/lib/node-textfile").
              '';
            }
          ];

          systemd.services.cardano-custom-metrics = {
            description = "Collect custom cardano metrics for the node-exporter textfile collector";

            # Soft Wants= (not Requires=) so the timer still fires if
            # cardano-node is wedged; the ping sample then goes absent
            # rather than the runs being silently skipped.
            after = ["cardano-node.service"];
            wants = ["cardano-node.service"];

            environment = {
              OUT = "${textfileDirectory}/cardano-custom-metrics.prom";
              inherit
                (config.environment.variables)
                TESTNET_MAGIC
                ;
            };

            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${collect}/bin/cardano-custom-metrics-collect";
              DynamicUser = true;
              SupplementaryGroups = ["node-textfile"];
              ReadWritePaths = [textfileDirectory];
              ProtectSystem = "strict";
              NoNewPrivileges = true;
              PrivateTmp = true;
              # Cap well below repeated timer firings so a hung ping doesn't
              # stack; systemd skips a trigger while the unit is still active.
              TimeoutStartSec = "45s";
            };
          };

          systemd.timers.cardano-custom-metrics = {
            wantedBy = ["timers.target"];
            timerConfig = {
              Unit = "cardano-custom-metrics.service";
              OnCalendar = "minutely";
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
        services.alloy.extraPrometheusRelabelNodeKeepRegex = ["^cardano_node_metrics_custom_ping_latency_ms$"];
      });
  };
}
