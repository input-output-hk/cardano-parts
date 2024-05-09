# nixosModule: profile-cardano-node-custom-metrics
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module
#   * This module will acquire additional relevant metrics not provided by node and push them to a statsd server if available
#   * The upstream cardano-node nixos service module should still be imported separately
#   * The cardano-parts profile-cardano-node-group nixosModule should still be imported separately
{
  flake.nixosModules.profile-cardano-node-custom-metrics = {
    config,
    pkgs,
    lib,
    ...
  }: let
    inherit (lib) mkOption;
    inherit (lib.types) port str;
    inherit (perNodeCfg.meta) cardanoNodePort hostAddr;
    inherit (perNodeCfg.pkgs) cardano-cli;

    perNodeCfg = config.cardano-parts.perNode;
    cfg = config.services.cardano-node-custom-metrics;
  in {
    options.services.cardano-node-custom-metrics = {
      address = mkOption {
        type = str;
        default = "localhost";
        description = "The default netdata statsd listening binding for udp and tcp.";
      };

      filter = mkOption {
        type = str;
        default = "statsd_cardano*";
        description = "The default netdata prometheus metrics exporter filter.";
      };

      port = mkOption {
        type = port;
        default = 8125;
        description = "The default netdata statsd listening port.";
      };
    };

    config = {
      services.netdata = {
        enable = true;
        configText = ''
          [statsd]
            bind to = udp:${cfg.address} tcp:${cfg.address}
            default port = ${toString cfg.port}

          [prometheus:exporter]
            send charts matching = ${cfg.filter}
        '';
      };

      systemd.services.cardano-node-custom-metrics = {
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

            echo "Pushing statsd metrics to port: ${toString cfg.port}; udp=$UDP"

            while [ -n "''${1}" ]; do
              printf "%s\n" "''${1}"
              shift
            done | ncat "''${UDP}" --send-only ${cfg.address} ${toString cfg.port} || return 1

            return 0
          }

          if CARDANO_PING_OUPUT=$(cardano-cli ping \
              --count=1 \
              --host=${hostAddr} \
              --port=${toString cardanoNodePort} \
              --magic="$TESTNET_MAGIC" \
              --quiet \
              --json); then
            CARDANO_PING_LATENCY=$(jq '.pongs[-1].sample * 1000' <<< "$CARDANO_PING_OUPUT")
          fi

          echo "cardano_ping_latency_ms:''${CARDANO_PING_LATENCY}|g"
          statsd "cardano_ping_latency_ms:''${CARDANO_PING_LATENCY}|g"
        '';
      };

      systemd.timers.cardano-node-custom-metrics = {
        timerConfig = {
          Unit = "cardano-node-custom-metrics.service";
          OnCalendar = "minutely";
        };
        wantedBy = ["timers.target"];
      };
    };
  };
}
