# nixosModule: service-cardano-faucet
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-faucet.acmeEmail
#   config.services.cardano-faucet.acmeProd
#   config.services.cardano-faucet.configFile
#   config.services.cardano-faucet.enable
#   config.services.cardano-faucet.enableAcme
#   config.services.cardano-faucet.faucetPort
#   config.services.cardano-faucet.group
#   config.services.cardano-faucet.openFirewallFaucet
#   config.services.cardano-faucet.openFirewallNginx
#   config.services.cardano-faucet.package
#   config.services.cardano-faucet.serverAliases
#   config.services.cardano-faucet.serverName
#   config.services.cardano-faucet.socketPath
#   config.services.cardano-faucet.supplementaryGroups
#   config.services.cardano-faucet.user
#
# Tips:
#   * This service-cardano-faucet nixos module provides a basic cardano-faucet service
{moduleWithSystem, ...}: {
  flake.nixosModules.service-cardano-faucet = moduleWithSystem ({config, ...}: nixos @ {
    pkgs,
    lib,
    name,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) bool listOf package port str;
      inherit (groupCfg.meta) domain;

      groupCfg = nixos.config.cardano-parts.cluster.group;
      perNodeCfg = nixos.config.cardano-parts.perNode;

      cfg = nixos.config.services.cardano-faucet;
    in {
      options = {
        services.cardano-faucet = {
          acmeEmail = mkOption {
            type = str;
            default = null;
            description = "The default contact email to be used for ACME certificate aquisition.";
          };

          acmeProd = mkOption {
            type = bool;
            default = true;
            description = "Whether to use the ACME TLS production server for certificate requests.";
          };

          configFile = mkOption {
            type = str;
            default = "/run/secrets/cardano-faucet.json";
            description = "The string path of the cardano-faucet configuration and secrets json file.";
          };

          enable = mkOption {
            type = bool;
            default = false;
            description = "Enable cardano-faucet, a basic faucet for cardano-node.";
          };

          enableAcme = mkOption {
            type = bool;
            default = true;
            description = "Whether to obtain an ACME TLS cert for serving cardano-faucet server via nginx.";
          };

          faucetPort = mkOption {
            type = port;
            default = 8090;
            description = "The cardano-faucet listener port.";
          };

          group = mkOption {
            type = str;
            default = "cardano-faucet";
            description = "The cardano-faucet daemon group to use.";
          };

          openFirewallFaucet = mkOption {
            type = bool;
            default = false;
            description = "Whether to open the firewall TCP port used by cardano-faucet.";
          };

          openFirewallNginx = mkOption {
            type = bool;
            default = false;
            description = "Whether to open the firewall TCP ports used by nginx: 80, 443";
          };

          package = mkOption {
            type = package;
            default = perNodeCfg.pkgs.cardano-faucet;
            description = "The cardano-faucet package that should be used.";
          };

          serverAliases = mkOption {
            type = listOf str;
            default = [];
            description = "Extra FQDN aliases to be added to the ACME TLS cert for serving cardano-faucet via nginx.";
          };

          serverName = mkOption {
            type = str;
            default = "${name}.${domain}";
            description = "The default server name for serving cardano-faucet via nginx.";
          };

          supplementaryGroups = mkOption {
            type = listOf str;
            default = ["cardano-node" "keys"];
            description = "Any supplementary groups which the cardano-faucet dynamic user should be a part of.";
          };

          socketPath = mkOption {
            type = str;
            default = "/run/cardano-node/node.socket";
            description = "The path to the local cardano-node socket file that cardano-faucet will use.";
          };

          user = mkOption {
            type = str;
            default = "cardano-faucet";
            description = "The cardano-faucet daemon user to use.";
          };
        };
      };

      config = mkIf cfg.enable {
        networking.firewall.allowedTCPPorts =
          optionals cfg.openFirewallFaucet [cfg.faucetPort]
          ++ optionals cfg.openFirewallNginx [80 443];

        systemd.services.cardano-faucet = {
          wantedBy = ["multi-user.target"];

          # Allow up to 10 failures with 30 second restarts in a 15 minute window
          # before entering failure state and alerting
          startLimitBurst = 10;
          startLimitIntervalSec = 900;

          environment = {
            CONFIG_FILE = cfg.configFile;
            CARDANO_NODE_SOCKET_PATH = cfg.socketPath;
            PORT = toString cfg.faucetPort;
          };

          preStart = ''
            while [ ! -S "$CARDANO_NODE_SOCKET_PATH" ]; do
              echo "Waiting 10 seconds for cardano node socket to become available at path: $CARDANO_NODE_SOCKET_PATH"
              sleep 10
            done
          '';

          script = "exec ${getExe cfg.package}";

          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            LimitNOFILE = 65535;
            Restart = "always";
            RestartSec = "30s";
            SupplementaryGroups = concatStringsSep " " cfg.supplementaryGroups;

            # To avoid extended ledger replays timing out and failing the service on preStart
            # while waiting for a socket.
            TimeoutStartSec = 3600;
          };
        };

        users.groups.${cfg.group} = {};
        users.users.${cfg.user} = {
          inherit (cfg) group;

          description = "cardano-faucet daemon user";
          isSystemUser = true;
        };

        security.acme = mkIf cfg.enableAcme {
          acceptTerms = true;
          defaults = {
            email = cfg.acmeEmail;
            server =
              if cfg.acmeProd
              then "https://acme-v02.api.letsencrypt.org/directory"
              else "https://acme-staging-v02.api.letsencrypt.org/directory";
          };
        };

        services.nginx = {
          enable = true;
          eventsConfig = "worker_connections 4096;";
          appendConfig = "worker_rlimit_nofile 16384;";
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          commonHttpConfig = ''
            log_format x-fwd '$remote_addr - $remote_user [$time_local] '
                             '"$scheme://$host" "$request" "$http_accept_language" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent" "$http_x_forwarded_for"';

            access_log syslog:server=unix:/dev/log x-fwd;
            limit_req_zone $binary_remote_addr zone=apiPerIP:100m rate=1r/s;
            limit_req_status 429;
          '';

          virtualHosts = {
            faucet = {
              inherit (cfg) serverAliases serverName;

              default = true;
              enableACME = cfg.enableAcme;
              forceSSL = cfg.enableAcme;
              locations = let
                publicPrefixes = [
                  "/basic-faucet"
                  "/delegate"
                  "/get-site-key"
                  "/send-money"
                ];
              in
                {
                  "/".root = pkgs.runCommand "nginx-root-dir" {} ''mkdir $out; echo -n "Ready" > $out/index.html'';
                }
                // genAttrs publicPrefixes (_: {proxyPass = "http://127.0.0.1:${toString cfg.faucetPort}";});
            };
          };
        };

        systemd.services.nginx.serviceConfig = {
          LimitNOFILE = 65535;
          LogNamespace = "nginx";
        };
      };
    });
}
