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
#   config.services.cardano-faucet.nginxPolicy.enable
#   config.services.cardano-faucet.nginxPolicy.locations
#   config.services.cardano-faucet.nginxPolicy.mapHashBucketSize
#   config.services.cardano-faucet.nginxPolicy.policyFile
#   config.services.cardano-faucet.nginxPolicy.secretName
#   config.services.cardano-faucet.nginxPolicy.status
#   config.services.cardano-faucet.nginxPolicy.variable
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
  flake.nixosModules.service-cardano-faucet = moduleWithSystem (_: nixos @ {
    pkgs,
    lib,
    name,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) bool int listOf nullOr package port str;
      inherit (groupCfg.meta) domain environmentName;
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (perNodeCfg.pkgs) cardano-cli;
      inherit (cardanoLib.environments.${environmentName}.nodeConfig) ByronGenesisFile;
      inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;

      groupCfg = nixos.config.cardano-parts.cluster.group;
      perNodeCfg = nixos.config.cardano-parts.perNode;

      cfg = nixos.config.services.cardano-faucet;
    in {
      key = ./service-cardano-faucet.nix;

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

          nginxPolicy = {
            enable = mkOption {
              type = bool;
              default = false;
              description = ''
                Whether to include an operator supplied nginx http-context snippet,
                deployed as a secret, and to have each location in `locations`
                return `status` whenever the variable named by `variable` is
                set.

                The snippet is typically a set of `map` blocks. It must set the
                variable to 0 for a request to proceed and to any other value for
                the location to return `status` instead.

                With `useSopsSecrets` the snippet is the sops secret `secretName`,
                stored in the group deploy secrets as
                `<node>-faucet-nginx-policy.conf` in binary format, and nginx
                reloads when it changes. Otherwise provide it at `policyFile`.
              '';
            };

            locations = mkOption {
              type = listOf str;
              default = ["/send-money"];
              description = "The faucet vhost locations subject to the policy.";
            };

            mapHashBucketSize = mkOption {
              type = nullOr int;
              default = 128;
              description = ''
                The nginx map_hash_bucket_size while the policy is enabled. A map
                key longer than the cache line, 64 bytes on most hosts, needs this
                raised or nginx fails to start. Null keeps the nginx default.
              '';
            };

            policyFile = mkOption {
              type = str;
              default = "/run/secrets/${cfg.nginxPolicy.secretName}";
              description = "The path of the policy snippet included into the nginx http context.";
            };

            secretName = mkOption {
              type = str;
              default = "cardano-faucet-nginx-policy.conf";
              description = "The sops secret name of the policy snippet when useSopsSecrets is true.";
            };

            status = mkOption {
              type = int;
              default = 429;
              description = "The HTTP status a listed location returns when the variable is set.";
            };

            variable = mkOption {
              type = str;
              default = "faucetPolicy";
              description = "The nginx variable, without the `$`, set by the policy snippet. 0 lets a request proceed, anything else returns `status`.";
            };
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

          # Ordering only. Deliberately not bindsTo or partOf: those propagate
          # the node's stop to this unit, and a unit stopped by a dependency is
          # not brought back by Restart=, so a node restart would leave the
          # faucet down until someone noticed. Crash plus Restart=always plus
          # the preStart gate below already recovers, and does so after the node
          # is usable rather than merely running.
          after = ["cardano-node.service"];
          wants = ["cardano-node.service"];

          path = [cardano-cli pkgs.jq];

          environment = {
            CONFIG_FILE = cfg.configFile;
            CARDANO_NODE_SOCKET_PATH = cfg.socketPath;
            CARDANO_NODE_NETWORK_ID =
              if environmentName == "mainnet"
              then "mainnet"
              else toString protocolMagic;
            PORT = toString cfg.faucetPort;
          };

          preStart = ''
            set -uo pipefail

            while [ ! -S "$CARDANO_NODE_SOCKET_PATH" ]; do
              echo "Waiting 10 seconds for cardano node socket to become available at path: $CARDANO_NODE_SOCKET_PATH"
              sleep 10
            done

            # The socket appears early in node startup, long before the ledger
            # has replayed. Starting here means the faucet's first chain query
            # sees whatever era replay has reached, and it exits on the era
            # mismatch. Wait for the node to reach tip, not merely to listen.
            while true; do
              SYNC=$(cardano-cli latest query tip 2> /dev/null | jq -r '.syncProgress // empty' 2> /dev/null) || SYNC=""

              if [ "$SYNC" = "100.00" ]; then
                echo "Node is synced, starting cardano-faucet"
                break
              fi

              echo "Waiting 10 seconds for cardano node sync, currently at ''${SYNC:-unknown}%"
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
          mapHashBucketSize = mkIf (cfg.nginxPolicy.enable && cfg.nginxPolicy.mapHashBucketSize != null) cfg.nginxPolicy.mapHashBucketSize;
          commonHttpConfig =
            ''
              log_format x-fwd '$remote_addr - $remote_user [$time_local] '
                               '"$scheme://$host" "$request" "$http_accept_language" $status $body_bytes_sent '
                               '"$http_referer" "$http_user_agent" "$http_x_forwarded_for"';

              access_log syslog:server=unix:/dev/log x-fwd;
              limit_req_zone $binary_remote_addr zone=apiPerIP:100m rate=1r/s;
              limit_req_status 429;
            ''
            + optionalString cfg.nginxPolicy.enable ''
              include ${cfg.nginxPolicy.policyFile};
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
                # Merged into the listed locations so each keeps its proxyPass.
                policy = "if (\$${cfg.nginxPolicy.variable}) { return ${toString cfg.nginxPolicy.status}; }";
              in
                mkMerge [
                  {"/".root = pkgs.runCommand "nginx-root-dir" {} ''mkdir $out; echo -n "Ready" > $out/index.html'';}
                  (genAttrs publicPrefixes (_: {proxyPass = "http://127.0.0.1:${toString cfg.faucetPort}";}))
                  (mkIf cfg.nginxPolicy.enable (genAttrs cfg.nginxPolicy.locations (_: {extraConfig = policy;})))
                ];
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
