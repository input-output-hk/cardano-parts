# nixosModule: profile-cardano-custom-metrics
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module
#   * This module will acquire additional cardano relevant metrics and push them to a statsd server if available
#   * The upstream cardano-node nixos service module should still be imported separately
#   * The cardano-parts profile-cardano-node-group nixosModule should still be imported separately
{
  flake.nixosModules.profile-cardano-custom-metrics = {
    config,
    pkgs,
    lib,
    ...
  }: let
    inherit (lib) mkIf mkOption;
    inherit (lib.types) bool port str;
    inherit (perNodeCfg.meta) cardanoNodePort hostAddr;
    inherit (perNodeCfg.pkgs) cardano-cli;

    perNodeCfg = config.cardano-parts.perNode;
    cfg = config.services.cardano-custom-metrics;
  in {
    options.services.cardano-custom-metrics = {
      address = mkOption {
        type = str;
        default = "localhost";
        description = "The default netdata statsd listening binding for udp and tcp.";
      };

      enableFilter = mkOption {
        type = bool;
        default = true;
        description = "Whether to filter netdata metrics exported to prometheus.";
      };

      filter = mkOption {
        type = str;
        default = "statsd_cardano*";
        description = "The default netdata prometheus metrics exporter filter.";
      };

      port = mkOption {
        type = port;
        default = 19999;
        description = "The default netdata listening port.";
      };

      statsdPort = mkOption {
        type = port;
        default = 8125;
        description = "The default netdata statsd listening port.";
      };
    };

    config = {
      services.netdata = {
        enable = true;

        config = {
          web."default port" = cfg.port;

          statsd = {
            "bind to" = "udp:${cfg.address} tcp:${cfg.address}";
            "default port" = cfg.statsdPort;
          };
        };

        configDir = mkIf cfg.enableFilter {
          "exporting.conf" = pkgs.writeText "exporting.conf" ''
            [prometheus:exporter]
              send charts matching = ${cfg.filter}
          '';
        };
      };

      systemd.services.cardano-custom-metrics = {
        path = with pkgs; [cardano-cli coreutils jq nmap];
        environment = {
          inherit
            (config.environment.variables)
            CARDANO_NODE_NETWORK_ID
            CARDANO_NODE_SOCKET_PATH
            TESTNET_MAGIC
            ;
        };
        script = ''
          statsd() {
            local UDP="-u" ALL="''${*}"

            # If the string length of all parameters given is above 1000, use TCP
            if [ "''${#ALL}" -gt 1000 ]; then
              UDP=
            fi

            echo "Pushing statsd metrics to port: ${toString cfg.statsdPort}; udp=$UDP"

            while [ -n "''${1}" ]; do
              printf "%s\n" "''${1}"
              shift
            done | ncat "''${UDP}" --send-only ${cfg.address} ${toString cfg.statsdPort} || return 1

            return 0
          }

          if CARDANO_NODE_PING_OUPUT=$(cardano-cli ping \
              --count=1 \
              --host=${hostAddr} \
              --port=${toString cardanoNodePort} \
              --magic="$TESTNET_MAGIC" \
              --quiet \
              --json); then
            CARDANO_NODE_PING_LATENCY=$(jq '.pongs[-1].sample * 1000' <<< "$CARDANO_NODE_PING_OUPUT")
          fi

          COREDUMPS=$(coredumpctl -S -1h --json=pretty 2>&1 || true)
          if [ "$COREDUMPS" = "No coredumps found." ]; then
            COREDUMPS_LAST_HOUR="0"
          else
            COREDUMPS_LAST_HOUR=$(jq -re '. | length' <<< "$COREDUMPS")
          fi

          echo "cardano.coredumps_last_hour:''${COREDUMPS_LAST_HOUR}|g"
          echo "cardano.node_ping_latency_ms:''${CARDANO_NODE_PING_LATENCY}|g"
          statsd \
            "cardano.coredumps_last_hour:''${COREDUMPS_LAST_HOUR}|g" \
            "cardano.node_ping_latency_ms:''${CARDANO_NODE_PING_LATENCY}|g" \
        '';
      };

      systemd.timers.cardano-custom-metrics = {
        timerConfig = {
          Unit = "cardano-custom-metrics.service";
          OnCalendar = "minutely";
        };
        wantedBy = ["timers.target"];
      };
    };
  };
}
