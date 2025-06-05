# nixosModule: profile-cardano-metadata
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-metadata.acmeEmail
#   config.services.cardano-metadata.acmeProd
#   config.services.cardano-metadata.enableAcme
#   config.services.cardano-metadata.enableProduction
#   config.services.cardano-metadata.metadataRamAvailableMiB
#   config.services.cardano-metadata.metadataRuntimeMaxSec
#   config.services.cardano-metadata.metadataServerPort
#   config.services.cardano-metadata.metadataSyncGitMetadataFolder
#   config.services.cardano-metadata.metadataSyncGitUrl
#   config.services.cardano-metadata.metadataWebhookPort
#   config.services.cardano-metadata.openFirewallNginx
#   config.services.cardano-metadata.postgresRamAvailableMiB
#   config.services.cardano-metadata.serverAliases
#   config.services.cardano-metadata.serverName
#   config.services.cardano-metadata.useSopsSecrets
#   config.services.cardano-metadata.varnishExporterPort
#   config.services.cardano-metadata.varnishMaxPostSizeBodyKiB
#   config.services.cardano-metadata.varnishMaxPostSizeCachableKiB
#   config.services.cardano-metadata.varnishRamAvailableMiB
#   config.services.cardano-metadata.varnishTtlMinutes
#
# Tips:
#   * This is a cardano-metadata profile add-on to the upstream metadata-[server|sync|webhook] nixos service modules
#   * This module assists with configuring a fully functioning metadata server
#   * The upstream metadata nixos service modules should still be imported separately
flake: {
  flake.nixosModules.profile-cardano-metadata = {
    config,
    pkgs,
    lib,
    name,
    nodeResources,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) bool float ints listOf nullOr oneOf port str;
      inherit (nodeResources) cpuCount memMiB;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) domain;
      inherit (perNodeCfg.pkgs.cardano-metadata-pkgs) metadata-server metadata-sync metadata-webhook;
      inherit (opsLib) mkSopsSecret;

      groupCfg = config.cardano-parts.cluster.group;
      perNodeCfg = config.cardano-parts.perNode;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      groupOutPath = groupFlake.self.outPath;

      roundFloat = f:
        if f >= (floor f + 0.5)
        then ceil f
        else floor f;

      cfg = config.services.cardano-metadata;
      cfgHook = config.services.metadata-webhook;
      cfgSrv = config.services.metadata-server;
      cfgSync = config.services.metadata-sync;
    in {
      imports = [flake.config.flake.nixosModules.module-nginx-vhost-exporter];

      key = ./profile-cardano-metadata.nix;

      options = {
        services.cardano-metadata = {
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

          enableAcme = mkOption {
            type = bool;
            default = true;
            description = "Whether to obtain an ACME TLS cert for serving metadata server via nginx.";
          };

          enableProduction = mkOption {
            type = bool;
            default = false;
            description = "Whether to use testnet or production metadata registries by default.";
          };

          metadataRamAvailableMiB = mkOption {
            description = "The default RAM available for metadata-server on the machine in MiB.";
            type = oneOf [ints.positive float];
            default = memMiB * 0.20;
          };

          metadataRuntimeMaxSec = mkOption {
            type = nullOr ints.positive;
            default = 12 * 3600;
            description = ''
              The maximum allowed runtime for metadata-server before systemd will automatically restart the service.
              This is one approach that can be used to limit memory consumption on a leaky service.
            '';
          };

          metadataServerPort = mkOption {
            type = port;
            default = 8080;
            description = "The port for the metadata server to listen on.";
          };

          metadataSyncGitMetadataFolder = mkOption {
            type = str;
            default =
              if cfg.enableProduction
              then "mappings"
              else "registry";
            description = ''
              The metadata-sync git URL folder to use.

              Typically for production, this would be: "mappings".
              Typically for testnets, this would be: "registry".
            '';
          };

          metadataSyncGitUrl = mkOption {
            type = str;
            default =
              if cfg.enableProduction
              then "https://github.com/cardano-foundation/cardano-token-registry.git"
              else "https://github.com/input-output-hk/metadata-registry-testnet.git";
            description = ''
              The metadata-sync git URL to use.

              Typically for production, this would be:
                https://github.com/cardano-foundation/cardano-token-registry.git

              Typically for testnets, this would be:
                https://github.com/input-output-hk/metadata-registry-testnet.git
            '';
          };

          metadataWebhookPort = mkOption {
            type = port;
            default = 8081;
            description = "The port for the metadata webhook server to listen on.";
          };

          openFirewallNginx = mkOption {
            type = bool;
            default = true;
            description = "Whether to open the firewall TCP ports used by nginx: 80, 443";
          };

          postgresRamAvailableMiB = mkOption {
            description = "The default RAM available for postgresql on the machine in MiB.";
            type = oneOf [ints.positive float];
            default = memMiB * 0.50;
          };

          serverAliases = mkOption {
            type = listOf str;
            default = [];
            description = "Extra FQDN aliases to be added to the ACME TLS cert for serving metadata server via nginx.";
          };

          serverName = mkOption {
            type = str;
            default = "${name}.${domain}";
            description = "The default server name for serving metadata server via nginx.";
          };

          useSopsSecrets = mkOption {
            type = bool;
            default = true;
            description = ''
              Whether to use the default configurated sops secrets if true,
              or user deployed secrets if false.

              If false, the following secret file, containing one secret
              indicated by filename, will need to be provided to the target
              machine either by additional module code or out of band:

                /run/secrets/cardano-metadata-webhook
            '';
          };

          varnishExporterPort = mkOption {
            type = port;
            default = 9131;
            description = "The port for the varnish metrics exporter to listen on.";
          };

          varnishMaxPostSizeBodyKiB = mkOption {
            type = ints.positive;
            default = 64;
            description = "The maximum POST size allowed for a metadata/query body payload.";
          };

          varnishMaxPostSizeCachableKiB = mkOption {
            type = ints.positive;
            default = 100;
            description = "The maximum cacheable POST size before varnish will disconnect and cause nginx to 502.";
          };

          varnishRamAvailableMiB = mkOption {
            type = oneOf [ints.positive float];
            default = memMiB * 0.20;
            description = "The max amount of RAM to allocate to for metadata server varnish object memory backend store.";
          };

          varnishTtlMinutes = mkOption {
            type = ints.positive;
            default = 30;
            description = "The number of minutes for metadata server cache object TTL.";
          };
        };
      };

      config = {
        systemd.services = {
          # Disallow metadata-server to restart more than 3 times within a 30 minute window
          # This ensures the service stops and an alert will get sent if there is a persistent restart issue
          # This also allows for some additional startup time before failure and restart
          #
          # If metadata-server fails and the service needs to be restarted manually before the 30 min window ends, run:
          # systemctl reset-failed metadata-server && systemctl start metadata-server
          metadata-server = {
            environment.GHCRTS = "-M${toString (roundFloat cfg.metadataRamAvailableMiB)}M";
            startLimitIntervalSec = 1800;
            startLimitBurst = 3;

            serviceConfig = {
              Restart = "always";
              RestartSec = "30s";

              # Limit memory and runtime until a memory leak is addressed
              MemoryMax = "${toString (128 + (roundFloat cfg.metadataRamAvailableMiB))}M";
              RuntimeMaxSec = mkIf (cfg.metadataRuntimeMaxSec != null) cfg.metadataRuntimeMaxSec;
            };
          };

          # See comment above for metadata-server regarding restarts; same applies for metadata-webhook service
          metadata-webhook = {
            startLimitIntervalSec = 1800;
            startLimitBurst = 3;

            serviceConfig = {
              Restart = "always";
              RestartSec = "30s";
            };
          };

          nginx.serviceConfig = {
            LimitNOFILE = 65535;
            LogNamespace = "nginx";
          };
        };

        services = {
          postgresql = {
            ensureDatabases = ["${cfgSrv.postgres.database}"];
            ensureUsers = [
              {
                name = "${cfgSrv.postgres.user}";
                ensureDBOwnership = true;
              }
            ];
            identMap = ''
              metadata-users root ${cfgSrv.postgres.user}
              metadata-users ${cfgSrv.user} ${cfgSrv.postgres.user}
              metadata-users ${cfgHook.user} ${cfgSrv.postgres.user}
              metadata-users ${cfgSync.user} ${cfgSrv.postgres.user}
              metadata-users postgres postgres
            '';
            authentication = ''
              local all all ident map=metadata-users
            '';
          };

          # Tune the amount of ram available to postgres
          cardano-postgres.ramAvailableMiB = cfg.postgresRamAvailableMiB;

          metadata-server = {
            enable = true;
            package = metadata-server;
            port = cfg.metadataServerPort;

            postgres = {
              # To utilize ensureDBOwnership in >= nixpkgs 23.11, the database and username must the same.
              database = "metadata";
              user = "metadata";
              numConnections = cpuCount;
            };
          };

          metadata-webhook = {
            enable = true;
            package = metadata-webhook;
            user = "metadata-webhook";
            port = cfg.metadataWebhookPort;
            environmentFile = "/run/secrets/cardano-metadata-webhook";
            postgres = {inherit (cfgSrv.postgres) socketdir port database table user numConnections;};
          };

          metadata-sync = {
            enable = true;
            package = metadata-sync;

            postgres = {inherit (cfgSrv.postgres) socketdir port database table user numConnections;};

            git = {
              repositoryUrl = cfg.metadataSyncGitUrl;
              metadataFolder = cfg.metadataSyncGitMetadataFolder;
            };
          };

          varnish = {
            enable = true;
            extraModules = [pkgs.varnishPackages.modules];
            extraCommandLine = "-t ${toString (cfg.varnishTtlMinutes * 60)} -s malloc,${toString (roundFloat cfg.varnishRamAvailableMiB)}M";
            config = ''
              vcl 4.1;

              import std;
              import bodyaccess;

              backend default {
                .host = "127.0.0.1";
                .port = "${toString cfg.metadataServerPort}";
              }

              acl purge {
                "localhost";
                "127.0.0.1";
              }

              sub vcl_recv {
                unset req.http.X-Body-Len;
                unset req.http.x-cache;

                # Allow PURGE from localhost
                if (req.method == "PURGE") {
                  if (!std.ip(req.http.X-Real-Ip, "0.0.0.0") ~ purge) {
                    return(synth(405,"Not Allowed"));
                  }

                  # If needed, host can be passed in the curl purge request with -H "Host: $HOST"
                  # along with an allow listed X-Real-Ip header.
                }

                # Allow POST caching
                # PURGE also needs to hash the body to obtain a correct object hash to purge
                if (req.method == "POST" || req.method == "PURGE") {
                  # Caches the body which enables POST retries if needed
                  std.cache_req_body(${toString cfg.varnishMaxPostSizeCachableKiB}KB);
                  set req.http.X-Body-Len = bodyaccess.len_req_body();

                  if ((std.integer(req.http.X-Body-Len, ${toString (1024 * cfg.varnishMaxPostSizeCachableKiB)}) > ${toString (1024 * cfg.varnishMaxPostSizeBodyKiB)}) ||
                      (req.http.X-Body-Len == "-1")) {
                    return(synth(413, "Payload Too Large"));
                  }

                  if (req.method == "PURGE") {
                    return(purge);
                  }
                  return(hash);
                }
              }

              sub vcl_hash {
                # For caching POSTs, hash the body also
                if (req.http.X-Body-Len) {
                  bodyaccess.hash_req_body();
                }
                else {
                  hash_data("");
                }
              }

              sub vcl_hit {
                set req.http.x-cache = "hit";
              }

              sub vcl_miss {
                set req.http.x-cache = "miss";
              }

              sub vcl_pass {
                set req.http.x-cache = "pass";
              }

              sub vcl_pipe {
                set req.http.x-cache = "pipe";
              }

              sub vcl_synth {
                set req.http.x-cache = "synth synth";
                set resp.http.x-cache = req.http.x-cache;
              }

              sub vcl_deliver {
                if (obj.uncacheable) {
                  set req.http.x-cache = req.http.x-cache + " uncacheable";
                }
                else {
                  set req.http.x-cache = req.http.x-cache + " cached";
                }
                set resp.http.x-cache = req.http.x-cache;
              }

              sub vcl_backend_fetch {
                if (bereq.http.X-Body-Len) {
                  set bereq.method = "POST";
                }
              }

              sub vcl_backend_response {
                if (beresp.status == 404) {
                  set beresp.ttl = ${toString (2 * cfg.varnishTtlMinutes / 3)}m;
                }
                call vcl_builtin_backend_response;
                return (deliver);
              }
            '';
          };

          nginx-vhost-exporter.enable = true;

          nginx = {
            enable = true;
            eventsConfig = "worker_connections 8192;";
            recommendedGzipSettings = true;
            recommendedOptimisation = true;
            recommendedProxySettings = true;

            commonHttpConfig = ''
              log_format x-fwd '$remote_addr - $remote_user $sent_http_x_cache [$time_local] '
                               '"$scheme://$host" "$request" $status $body_bytes_sent '
                               '"$http_referer" "$http_user_agent" "$http_x_forwarded_for"';

              access_log syslog:server=unix:/dev/log x-fwd if=$loggable;

              limit_req_zone $binary_remote_addr zone=metadataQueryPerIP:100m rate=10r/s;
              limit_req_status 429;
              server_names_hash_bucket_size 128;

              map $sent_http_x_cache $loggable_varnish {
                default 1;
                "hit cached" 0;
              }

              map $request_uri $loggable {
                /status/format/prometheus 0;
                default $loggable_varnish;
              }

              map $request_method $upstream_location {
                GET     127.0.0.1:6081;
                default 127.0.0.1:${toString cfg.metadataServerPort};
              }
            '';

            virtualHosts = {
              metadata = {
                inherit (cfg) serverAliases serverName;

                default = true;
                enableACME = cfg.enableAcme;
                forceSSL = cfg.enableAcme;

                locations = let
                  corsConfig = ''
                    add_header 'Vary' 'Origin' always;
                    add_header 'Access-Control-Allow-Methods' 'GET, PATCH, OPTIONS' always;
                    add_header 'Access-Control-Allow-Headers' 'User-Agent,X-Requested-With,Content-Type' always;

                    if ($request_method = OPTIONS) {
                      add_header 'Access-Control-Max-Age' 86400;
                      add_header 'Content-Type' 'text/plain; charset=utf-8';
                      add_header 'Content-Length' 0;
                      return 204;
                    }
                  '';
                  serverEndpoints = [
                    "/metadata/query"
                    "/metadata"
                  ];
                  webhookEndpoints = [
                    "/webhook"
                  ];
                in
                  {
                    "/".root = pkgs.runCommand "nginx-root-dir" {} ''mkdir $out; echo -n "Ready" > $out/index.html'';
                  }
                  // (recursiveUpdate (genAttrs serverEndpoints (_: {
                      proxyPass = "http://$upstream_location";
                      extraConfig = corsConfig;
                    })) {
                      # Uncomment to add varnish caching for all request on `/metadata/query` endpoint:
                      # "/metadata/query".proxyPass = "http://127.0.0.1:6081";
                      "/metadata/query".extraConfig = ''
                        limit_req zone=metadataQueryPerIP burst=20 nodelay;
                        ${corsConfig}
                      '';
                      "/metadata/healthcheck".extraConfig = ''
                        add_header Content-Type text/plain;
                        return 200 'OK';
                      '';
                    })
                  // (genAttrs webhookEndpoints (p: {
                    proxyPass = "http://127.0.0.1:${toString cfg.metadataWebhookPort}${p}";
                    extraConfig = corsConfig;
                  }));
              };
            };
          };

          prometheus.exporters = {
            varnish = {
              enable = true;
              listenAddress = "127.0.0.1";
              port = cfg.varnishExporterPort;
              group = "varnish";

              # Required until https://github.com/nixos/nixpkgs/issues/400003 is fixed.
              instance =
                if versionOlder config.services.varnish.package.version "7"
                then "/var/run/varnish/${config.networking.hostName}"
                else "/var/run/varnishd";
            };
          };
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewallNginx [80 443];

        # For the webhook service, a non-dynamic user is required for user and group file assignment to the sops secret,
        # which gets created before a dynamic user and group is available:
        users = {
          groups.metadata-webhook = {};
          users.metadata-webhook = {
            group = "metadata-webhook";
            isSystemUser = true;
          };
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

        sops.secrets = mkIf cfg.useSopsSecrets (mkSopsSecret {
          secretName = "cardano-metadata-webhook";
          keyName = "${name}-metadata-webhook";
          inherit groupOutPath groupName name;
          fileOwner = "metadata-webhook";
          fileGroup = "metadata-webhook";
          restartUnits = ["metadata-webhook.service"];
        });
      };
    };
}
