# nixosModule: profile-monitoring
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   (None — this profile reads its configuration from flake-level
#   `flake.cardano-parts.cluster.infra.monitoring` options.)
#
# Tips:
#   * This module provides an in-cluster Grafana + Mimir + Loki + Prometheus
#     monitoring stack, fronted by Caddy with ACME-issued TLS.
#   * It is intended to be imported on the single Colmena machine matching
#     `flake.cardano-parts.cluster.infra.monitoring.hostname` (default
#     "monitoring"). Group separation is handled at the alloy label level
#     in `profile-grafana-alloy`.
#   * The downstream consuming repo must provide the following sops secrets
#     under `secrets/monitoring/` of the consuming repo:
#       - grafana-password.enc
#       - grafana-oauth-client-id.enc
#       - grafana-oauth-client-secret.enc
#       - caddy-environment-${machineName}.enc
flake: {
  flake.nixosModules.profile-monitoring = {
    config,
    lib,
    name,
    pkgs,
    ...
  }:
    with lib; let
      # Cluster infra is read through groupFlake (the consuming flake's
      # `self`) rather than `flake.config`. `flake` here closes over
      # cardano-parts' OWN flake-parts evaluation, where these options
      # carry their declared defaults (null), not the consumer's values.
      inherit (groupFlake.config.flake.cardano-parts.cluster.infra) aws monitoring;
      inherit (aws) domain region;
      inherit (monitoring) bucketLoki bucketMimir email provisionPath retentionLogsDays retentionMetricsDays subdomain;

      # Derive duration strings for the apps. The S3-side retention is
      # driven by the same day-int through the bucket lifecycle config in
      # opentofu/bootstrap.nix, so app-level and storage-level retention
      # cannot drift.
      retentionLogs = "${toString retentionLogsDays}d";
      retentionMetrics = "${toString retentionMetricsDays}d";

      inherit (groupCfg) groupName groupFlake;
      inherit (opsLib) mkSopsSecret parseDir readNixImport;

      groupCfg = config.cardano-parts.cluster.group;
      groupOutPath = groupFlake.self.outPath;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      fqdn = "${subdomain}.${domain}";

      mimirHttpPort = config.services.mimir.configuration.server.http_listen_port;
      lokiHttpPort = config.services.loki.configuration.server.http_listen_port;

      # Translate a tofu-mimir-provider rule_group attrset into the shape
      # mimirtool's `rules sync` expects. Existing files in downstream repos
      # were authored against the tofu provider schema and must keep working
      # there; this transform stays at eval-time so the on-disk files don't
      # need to change.
      transformRuleGroup = src: {
        inherit (src) namespace;
        groups = [
          {
            inherit (src) name;
            rules = src.rule;
          }
        ];
      };

      readRuleFile = readNixImport groupFlake.self;

      ruleFiles = lib.optionals (provisionPath != null) (
        parseDir "${provisionPath}/alerts" ".nix-import"
        ++ parseDir "${provisionPath}/recording-rules" ".nix-import"
      );

      mimirRulesDir = pkgs.linkFarm "mimir-rules" (map (f: let
          rule = readRuleFile f;
          filename = "${rule.namespace}-${rule.name}.json";
        in {
          name = filename;
          path = pkgs.writeText filename (builtins.toJSON (transformRuleGroup rule));
        })
        ruleFiles);

      # Mimir alertmanager refuses to start with empty config, so a stub is
      # always written. When the consumer provides
      # `${provisionPath}/alertmanager.nix-import`, that replaces the stub.
      # The expected schema is upstream Prometheus alertmanager (single
      # `route` object, plural `receivers` list); secrets should reference
      # sops-managed files via the `*_file` suffix fields documented at
      # https://prometheus.io/docs/alerting/latest/configuration/.
      alertmanagerConfig = let
        path = "${provisionPath}/alertmanager.nix-import";
      in
        if provisionPath != null && builtins.pathExists path
        then readRuleFile path
        else {
          route = {
            group_wait = "0s";
            receiver = "empty-receiver";
          };
          receivers = [{name = "empty-receiver";}];
        };

      alertmanagerConfigFile = pkgs.writeText "alertmanager.yaml" (builtins.toJSON alertmanagerConfig);

      mimirRulesSync = pkgs.writeShellScript "mimir-rules-sync" ''
        set -euo pipefail
        # mimir runs single-tenant when multitenancy_enabled = false; the
        # implicit tenant id is "anonymous", which mimirtool needs explicitly.
        exec ${config.services.mimir.package}/bin/mimirtool rules sync \
          --address http://127.0.0.1:${toString mimirHttpPort}/mimir \
          --id anonymous \
          ${mimirRulesDir}/*.json
      '';

      mkSopsSecretParams = {
        secretName,
        keyName,
        fileOwner,
        restartUnit,
      }: {
        inherit groupOutPath groupName name secretName keyName fileOwner;
        fileGroup = fileOwner;
        pathPrefix = "${groupOutPath}/secrets/monitoring/";
        restartUnits = [restartUnit];
      };

      grafanaSecret = secretName:
        mkSopsSecret (mkSopsSecretParams {
          inherit secretName;
          keyName = "${secretName}.enc";
          fileOwner = "grafana";
          restartUnit = "grafana.service";
        });

      caddySecret = mkSopsSecret (mkSopsSecretParams {
        secretName = "caddy-environment";
        keyName = "caddy-environment-${name}.enc";
        fileOwner = "caddy";
        restartUnit = "caddy.service";
      });

      googleDomains = monitoring.oauth.google.allowedDomains;
    in {
      key = ./profile-monitoring.nix;

      config = {
        assertions = [
          {
            assertion = googleDomains != [];
            message = ''
              profile-monitoring requires a non-empty
              `flake.cardano-parts.cluster.infra.monitoring.oauth.google.allowedDomains`
              so that Grafana Google OAuth is restricted to a known tenant.
            '';
          }
          {
            assertion = email != null;
            message = ''
              profile-monitoring requires
              `flake.cardano-parts.cluster.infra.monitoring.email` to be set;
              Caddy uses it as the ACME contact for the Grafana virtual host.
            '';
          }
        ];

        sops.secrets =
          grafanaSecret "grafana-password"
          // grafanaSecret "grafana-oauth-client-id"
          // grafanaSecret "grafana-oauth-client-secret"
          // caddySecret;

        # Allow HTTP (for ACME) and HTTPS.
        networking.firewall.allowedTCPPorts = [80 443];

        systemd.services = {
          # No existing NixOS option exposes Caddy environment files cleanly.
          # Inject sops-managed secrets here; reference them in the Caddyfile
          # as e.g. {$ADMIN_HASH}.
          caddy.serviceConfig.EnvironmentFile = config.sops.secrets.caddy-environment.path;

          # Avoid grafana failing on reboot due to a secrets utilization race
          # condition. Cap the wait so a misconfigured sops setup fails the
          # unit instead of stalling multi-user.target indefinitely.
          grafana.preStart = ''
            for _ in $(seq 1 60); do
              [ -f ${config.sops.secrets.grafana-password.path} ] && exit 0
              echo "Waiting for grafana secrets to become available..."
              sleep 5
            done
            echo "ERROR: grafana sops secrets did not appear within 5 minutes" >&2
            exit 1
          '';

          # Avoid mimir failing on reboot due to a network interface not yet
          # being available when it tries to bind.
          mimir = {
            # Cap retries so a permanently-broken mimir doesn't generate
            # boot-loop journal noise. RestartSec=10s combined with these
            # bounds gives ~5 attempts per 10-minute window before failing
            # the unit and waiting for operator intervention.
            startLimitIntervalSec = 600;
            startLimitBurst = 5;

            serviceConfig = {
              Restart = "always";
              RestartSec = "10s";
            };
          };

          # Push provisioned alerting + recording rule_groups into Mimir on
          # boot. Idempotent: mimirtool diff/sync is content-addressed.
          mimir-rules-sync = mkIf (ruleFiles != []) {
            description = "Sync Mimir rules from cardano-parts provisionPath";
            after = ["mimir.service" "network-online.target"];
            requires = ["mimir.service"];
            wants = ["network-online.target"];
            wantedBy = ["multi-user.target"];

            # Cap retries so a permanently-broken mimir doesn't generate
            # boot-loop journal noise. The 10s RestartSec would otherwise
            # reset the default 10s start-limit window before it accumulates.
            startLimitIntervalSec = 600;
            startLimitBurst = 5;

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = mimirRulesSync;
              # Retry briefly if mimir hasn't bound its listener yet.
              Restart = "on-failure";
              RestartSec = "10s";
            };
          };
        };

        services = {
          grafana = {
            enable = true;

            settings = {
              # AlertManager (via Mimir) is the alerting source of truth.
              alerting.enabled = false;

              analytics.reporting_enabled = false;

              "auth.anonymous".enabled = false;

              security.admin_password = "$__file{${config.sops.secrets.grafana-password.path}}";

              unified_alerting.enabled = true;

              users.auto_assign_org_role = "Editor";

              server = {
                domain = fqdn;
                root_url = "https://${fqdn}/";

                # Caddy already does compression.
                enable_gzip = false;

                # Block DNS rebinding.
                enforce_domain = true;
              };

              "auth.google" = {
                enabled = true;
                allow_sign_up = true;
                auto_login = false;
                client_id = "$__file{${config.sops.secrets.grafana-oauth-client-id.path}}";
                client_secret = "$__file{${config.sops.secrets.grafana-oauth-client-secret.path}}";
                scopes = "openid email profile";
                auth_url = "https://accounts.google.com/o/oauth2/v2/auth";
                token_url = "https://oauth2.googleapis.com/token";
                api_url = "https://openidconnect.googleapis.com/v1/userinfo";
                allowed_domains = concatStringsSep " " googleDomains;
                hosted_domain = head googleDomains;
                use_pkce = true;
              };
            };

            provision = {
              enable = true;

              dashboards.settings = mkIf (provisionPath != null) {
                apiVersion = 1;
                providers = [
                  {
                    name = "default";
                    type = "file";
                    options.path = "${provisionPath}/dashboards";
                    # Use the directory tree under `dashboards/` as Grafana folder structure.
                    foldersFromFilesStructure = true;
                    # Allow operators to edit provisioned dashboards in the UI.
                    # Edits are reverted on each redeploy.
                    allowUiUpdates = true;
                  }
                ];
              };

              datasources.settings.datasources =
                [
                  {
                    type = "prometheus";
                    name = "Mimir";
                    uid = "mimir";
                    isDefault = true;
                    url = "http://127.0.0.1:${toString mimirHttpPort}/mimir/prometheus";
                    jsonData.timeInterval = "60s";
                  }
                  {
                    type = "alertmanager";
                    name = "Alertmanager";
                    uid = "alertmanager_mimir";
                    url = "http://127.0.0.1:${toString mimirHttpPort}/mimir";
                    jsonData = {
                      implementation = "mimir";
                      handleGrafanaManagedAlerts = true;
                    };
                  }
                ]
                ++ optional config.services.loki.enable {
                  type = "loki";
                  name = "Loki";
                  uid = "loki";
                  url = "http://127.0.0.1:${toString lokiHttpPort}";
                  jsonData.manageAlerts = true;
                };
            };
          };

          mimir = {
            enable = true;

            configuration = {
              common.storage = {
                backend = "s3";
                s3 = {
                  inherit region;
                  bucket_name = bucketMimir;
                  endpoint = "s3.amazonaws.com";
                };
              };

              target = "all,alertmanager";

              blocks_storage.storage_prefix = "blocks";

              ruler.alertmanager_url = "http://127.0.0.1:${toString mimirHttpPort}/mimir/alertmanager";

              limits = {
                compactor_blocks_retention_period = retentionMetrics;
                # Allow ingestion of out-of-order samples up to 5 minutes since
                # the latest received sample for the series.
                out_of_order_time_window = "5m";
              };

              compactor = {
                # Persistent path: compactor stages multi-GB blocks before
                # uploading. /tmp on systemd is tmpfs (RAM-backed), which
                # would OOM the host once retention windows accumulate.
                data_dir = "/var/lib/mimir/compactor";
                sharding_ring.kvstore.store = "memberlist";
              };

              distributor.ring = {
                instance_addr = "127.0.0.1";
                kvstore.store = "memberlist";
              };

              ingester.ring = {
                instance_addr = "127.0.0.1";
                kvstore.store = "memberlist";
                replication_factor = 1;
              };

              multitenancy_enabled = false;

              # Help prevent "too many outstanding requests" errors.
              frontend.max_outstanding_per_tenant = 256;

              server = {
                http_listen_port = 8080;
                http_listen_address = "127.0.0.1";
                http_path_prefix = "/mimir";
                log_request_headers = true;
              };

              store_gateway.sharding_ring.replication_factor = 1;

              usage_stats.enabled = false;

              alertmanager = {
                external_url = "https://${fqdn}/mimir/alertmanager";
                data_dir = "/var/lib/mimir/alertmanager";
                fallback_config_file = alertmanagerConfigFile;
              };
            };
          };

          caddy = {
            enable = true;
            enableReload = true;
            inherit email;

            virtualHosts."${fqdn}".extraConfig =
              ''
                # Caddy `handle` blocks are mutually exclusive and most-specific
                # wins. The narrower `/mimir/api/v1/push` and `/loki/api/v1/push`
                # write-hash routes must remain split from the broader
                # `/mimir/*` and `/loki/*` admin-hash routes; do not collapse them.
                encode zstd gzip

                handle /blackbox/* {
                  basicauth { admin {$ADMIN_HASH} }
                  reverse_proxy 127.0.0.1:9115
                }

                handle /mimir/api/v1/push {
                  basicauth { write {$WRITE_HASH} }
                  reverse_proxy 127.0.0.1:${toString mimirHttpPort}
                }

                handle /mimir/* {
                  basicauth { admin {$ADMIN_HASH} }
                  reverse_proxy 127.0.0.1:${toString mimirHttpPort}
                }
              ''
              + optionalString config.services.loki.enable ''
                handle /loki/api/v1/push {
                  basicauth { write {$WRITE_HASH} }
                  reverse_proxy 127.0.0.1:${toString lokiHttpPort}
                }

                handle /loki/* {
                  basicauth { admin {$ADMIN_HASH} }
                  uri strip_prefix /loki
                  reverse_proxy 127.0.0.1:${toString lokiHttpPort}
                }

                handle /otlp/v1/logs {
                  basicauth { write {$WRITE_HASH} }
                  reverse_proxy 127.0.0.1:${toString lokiHttpPort}
                }
              ''
              + ''
                handle /* {
                  reverse_proxy 127.0.0.1:${toString config.services.grafana.settings.server.http_port}
                }
              '';
          };

          prometheus = {
            enable = true;

            alertmanagers = [
              {
                scheme = "http";
                path_prefix = "/mimir";
                static_configs = [{targets = ["127.0.0.1:${toString mimirHttpPort}"];}];
              }
            ];

            exporters.blackbox = {
              enable = true;
              configFile = pkgs.writeText "blackbox-exporter.json" (builtins.toJSON {
                modules.https_2xx = {
                  prober = "http";
                  timeout = "5s";
                  http.fail_if_not_ssl = true;
                  http.preferred_ip_protocol = "ip4";
                };
              });
            };
          };

          loki = {
            enable = mkDefault true;

            configuration = {
              auth_enabled = false;

              limits_config.retention_period = retentionLogs;

              common = {
                ring.kvstore.store = "inmemory";
                replication_factor = 1;
              };

              server = {
                http_listen_port = 3100;
                grpc_listen_port = 3101;
              };

              compactor = {
                working_directory = "/var/lib/loki/compactor";
                compaction_interval = "10m";
                retention_enabled = true;
                retention_delete_delay = "2h";
                retention_delete_worker_count = 150;
                delete_request_store = "s3";
              };

              storage_config = {
                tsdb_shipper = {
                  active_index_directory = "/var/lib/loki/index/active";
                  cache_location = "/var/lib/loki/index/cache";
                };

                aws = {
                  s3 = "s3://${region}";
                  bucketnames = bucketLoki;
                };
              };

              schema_config.configs = [
                {
                  from = "2024-07-16";
                  store = "tsdb";
                  object_store = "s3";
                  schema = "v13";
                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];

              ruler = {
                alertmanager_url = "http://127.0.0.1:${toString mimirHttpPort}/mimir/alertmanager";
                storage = {
                  type = "s3";
                  s3 = {
                    s3 = "s3://${region}";
                    bucketnames = bucketLoki;
                  };
                };
                rule_path = "/var/lib/loki/rules";
                ring.kvstore.store = "inmemory";
              };
            };
          };
        };
      };
    };
}
