# nixosModule: profile-grafana-alloy
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.alloy.enableLiveDebugging
#   config.services.alloy.extraAlloyConfig
#   config.services.alloy.labels
#   config.services.alloy.logLevel
#   config.services.alloy.prometheusExporterUnixNodeSetCollectors
#   config.services.alloy.prometheusRelabelNodeKeepRegex
#   config.services.alloy.systemdEnableRestartMetrics
#   config.services.alloy.systemdEnableStartTimeMetrics
#   config.services.alloy.systemdEnableTaskMetrics
#   config.services.alloy.systemdUnitExclude
#   config.services.alloy.systemdUnitInclude
#   config.services.alloy.useSopsSecrets
#
# Tips:
#   * This module provides a grafana-alloy service and configures common application metrics hooks
flake @ {moduleWithSystem, ...}: {
  flake.nixosModules.profile-grafana-alloy = moduleWithSystem ({inputs'}: {
    config,
    lib,
    name,
    pkgs,
    self,
    ...
  }:
    with builtins;
    with lib; let
      inherit (lib.types) attrsOf bool enum listOf str lines;
      inherit (config.cardano-parts.perNode.meta) cardanoDbSyncPrometheusExporterPort cardanoNodePrometheusExporterPort hostAddr;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) environmentName;
      inherit (opsLib) mkSopsSecret;

      groupCfg = config.cardano-parts.cluster.group;
      groupOutPath = groupFlake.self.outPath;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      mkSopsSecretParams = secretName: {
        inherit groupOutPath groupName name secretName;
        keyName = secretName + ".enc";
        # Setting grafana-alloy service to a non-dynamic user allows constraining the secrets file to non-root ownership
        fileOwner = "grafana-alloy";
        fileGroup = "grafana-alloy";
        pathPrefix = "${groupOutPath}/secrets/monitoring/";
        restartUnits = ["alloy.service"];
      };

      alloyComponentCfg = {
        logging = ''
          // Log setup
          logging {
            level = "${toString cfg.logLevel}"
            format = "logfmt"
          }

        '';

        livedebugging = ''
          // Live debug setup: experimental, but useful for relabel component investigation
          livedebugging {
            enabled = ${boolToString cfg.enableLiveDebugging}
          }

        '';

        secrets = ''
          // Secrets
          local.file "remote_write_url" {
            filename = "/run/secrets/grafana-alloy-metrics-url"
          }

          local.file "remote_write_username" {
            filename = "/run/secrets/grafana-alloy-metrics-username"
          }

          local.file "remote_write_password" {
            filename = "/run/secrets/grafana-alloy-metrics-password"
            is_secret = true
          }

        '';

        remoteWrite = ''
          // Default prometheus remote write target
          prometheus.remote_write "integrations" {
            endpoint {
              url = local.file.remote_write_url.content

              basic_auth {
                username = local.file.remote_write_username.content
                password = local.file.remote_write_password.content
              }
            }
          }

        '';

        alloy = ''
          // Default grafana alloy integration components, in lowest to highest dependency order
          prometheus.exporter.self "integrations_alloy" {}

          discovery.relabel "integrations_alloy" {
            targets = prometheus.exporter.self.integrations_alloy.targets

            rule {
              source_labels = ["alloy_hostname"]
              target_label = "instance"
            }

            rule {
              regex = "^alloy_hostname$"
              action = "labeldrop"
            }

            rule {
              target_label = "instance"
              replacement = "${name}"
            }

            rule {
              target_label = "job"
              replacement = "integrations/alloy-check"
            }
          }

          prometheus.scrape "integrations_alloy" {
            targets = discovery.relabel.integrations_alloy.output
            forward_to = [prometheus.relabel.integrations_alloy.receiver]
            job_name = "integrations/alloy"
          }

          prometheus.relabel "integrations_alloy" {
            forward_to = [prometheus.remote_write.integrations.receiver]

            rule {
              source_labels = ["__name__"]
              regex = "${cfg.prometheusRelabelAlloyKeepRegex}"
              action = "keep"
            }
          }

        '';

        exporter = ''
          // Default grafana alloy node exporter integration components, in lowest to highest dependency order
          prometheus.exporter.unix "integrations_node_exporter" {
            set_collectors = [${concatMapStringsSep ", " (s: "\"${s}\"") cfg.prometheusExporterUnixNodeSetCollectors}]

            systemd {
              enable_restarts = ${boolToString cfg.systemdEnableRestartMetrics}
              start_time = ${boolToString cfg.systemdEnableStartTimeMetrics}
              task_metrics = ${boolToString cfg.systemdEnableTaskMetrics}
              unit_exclude = "${cfg.systemdUnitExclude}"
              unit_include = "${cfg.systemdUnitInclude}"
            }
          }

          discovery.relabel "integrations_node_exporter" {
            targets = prometheus.exporter.unix.integrations_node_exporter.targets

            rule {
              source_labels = ["alloy_hostname"]
              target_label = "instance"
            }

            rule {
              regex = "^alloy_hostname$"
              action = "labeldrop"
            }

            rule {
              target_label = "instance"
              replacement = "${name}"
            }

            rule {
              target_label = "job"
              replacement = "integrations/node_exporter"
            }
          }

          prometheus.scrape "integrations_node_exporter" {
            targets = discovery.relabel.integrations_node_exporter.output
            forward_to = [prometheus.relabel.integrations_node_exporter.receiver]
            job_name = "integrations/node_exporter"
          }

          prometheus.relabel "integrations_node_exporter" {
            forward_to = [prometheus.remote_write.integrations.receiver]

            rule {
              source_labels = ["__name__"]
              regex = "${cfg.prometheusRelabelNodeKeepRegex}"
              action = "keep"
            }

            rule {
              source_labels = ["__name__"]
              regex = "^node_filesystem_readonly$"
              action = "drop"
            }

            rule {
              source_labels = ["mountpoint"]
              regex = "^|/|/boot|/state|/home|/nix$"
              action = "keep"
            }

            rule {
              source_labels = ["mode"]
              regex = "^|system|user|iowait|steal|idle$"
              action = "keep"
            }
          }

        '';
      };

      cardanoPartsComponentCfg = {
        blockperf = optional (cfgSvc ? blockperf) ''
          // Blockperf integration component
          prometheus.scrape "integrations_blockperf" {
            targets = [{
              __address__ = "127.0.0.1:${toString config.services.blockperf.port}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.relabel.integrations_blockperf.receiver]
            job_name = "integrations/blockperf"
            metrics_path = "/"

            // Normally we prefer 1 minute default however we need
            // higher frequency with blockperf to catch large block
            // header delays.
            scrape_interval = "10s"
          }

          prometheus.relabel "integrations_blockperf" {
            forward_to = [prometheus.remote_write.integrations.receiver]
            rule {
              source_labels = ["__name__"]
              regex = "^blockperf_.*$"
              action = "keep"
            }
          }

        '';

        cardanoCustomMetrics = optional (cfgSvc ? cardano-custom-metrics && cfgSvc.netdata.enable) ''
          // Cardano custom metrics integration component
          prometheus.scrape "integrations_cardano_custom_metrics" {
            targets = [{
              __address__ = "${cfgSvc.cardano-custom-metrics.address}:${toString cfgSvc.cardano-custom-metrics.port}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.remote_write.integrations.receiver]
            job_name = "integrations/cardano-custom-metrics"
            params = {
              format = ["prometheus"],
              // Filtering here won't work as grafana-alloy encodes the
              // pattern match. Filtering can be configured from the
              // profile-cardano-custom-metrics nixosModule with the
              // `enableFilter` and `filter` options.
              // filter = ["statsd_cardano*"]
            }
            metrics_path = "/api/v1/allmetrics"
          }

        '';

        cardanoDbSync = optional (cfgSvc ? cardano-db-sync && cfgSvc.cardano-db-sync.enable) ''
          // Cardano-db-sync integration component
          prometheus.scrape "integrations_cardano_db_sync" {
            targets = [{
              __address__ = "${hostAddr}:${toString cardanoDbSyncPrometheusExporterPort}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.remote_write.integrations.receiver]
            job_name = "integrations/cardano-db-sync"
            metrics_path = "/"
          }

        '';

        cardanoFaucet = optional (cfgSvc ? cardano-faucet && cfgSvc.cardano-faucet.enable) ''
          // Cardano-faucet integration component
          prometheus.scrape "integrations_cardano_faucet" {
            targets = [{
              __address__ = "127.0.0.1:${toString cfgSvc.cardano-faucet.faucetPort}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.remote_write.integrations.receiver]
            job_name = "integrations/cardano-faucet"
            metrics_path = "/metrics"
          }

        '';

        cardanoNode = optionals (cfgSvc ? cardano-node && cfgSvc.cardano-node.enable) (map (
          i: let
            metricsPath =
              if cfgSvc.cardano-node.useLegacyTracing || (!cfgSvc.cardano-node.useLegacyTracing && cfgSvc.cardano-node.ngTracer)
              then "/metrics"
              else "/${(cfgSvc.cardano-node.extraNodeInstanceConfig i).TraceOptionNodeName}";

            serviceName = i:
              if i == 0
              then "cardano-node"
              else "cardano-node-${toString i}";

            target =
              if cfgSvc.cardano-node.useLegacyTracing
              then "${hostAddr}:${toString (cardanoNodePrometheusExporterPort + i)}"
              else if cfgSvc.cardano-node.ngTracer
              then "${hostAddr}:${toString (cardanoNodePrometheusExporterPort + i)}"
              else "${hostAddr}:${toString cardanoNodePrometheusExporterPort}";

            toUnderscore = s: replaceStrings ["-"] ["_"] s;
          in ''

            // Cardano-node instance ${toString i} integration component
            prometheus.scrape "integrations_${toUnderscore (serviceName i)}" {
              targets = [{
                __address__ = "${target}",
                instanceNum = "${toString i}",
                ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
              }]
              forward_to = [prometheus.remote_write.integrations.receiver]
              job_name = "integrations/${serviceName i}"
              metrics_path = "${metricsPath}"
            }

          ''
        ) (range 0 (cfgSvc.cardano-node.instances - 1)));

        cardanoSmash = optional (cfgSvc ? cardano-smash) ''
          // Cardano-smash integration component
          prometheus.scrape "integrations_cardano_smash" {
            targets = [{
              __address__ = "${hostAddr}:${toString cfgSvc.cardano-smash.registeredRelaysExporterPort}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.remote_write.integrations.receiver]
            job_name = "integrations/cardano-smash"
            metrics_path = "/"
          }

        '';

        mithrilSigner = optional (cfgSvc ? mithril-signer && cfgSvc.mithril-signer.enable && cfgSvc.mithril-signer.enableMetrics) ''
          // Mithril-signer integration component
          prometheus.scrape "integrations_mithril_signer" {
            targets = [{
              __address__ = "${cfgSvc.mithril-signer.metricsAddress}:${toString cfgSvc.mithril-signer.metricsPort}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.remote_write.integrations.receiver]
            job_name = "integrations/mithril-signer"
            metrics_path = "/metrics"
          }

        '';

        nginxVts = optional (cfgSvc ? nginx-vhost-exporter && cfgSvc.nginx-vhost-exporter.enable) ''
          // Nginx-vts integration component
          prometheus.scrape "integrations_nginx_vts" {
            targets = [{
              __address__ = "${cfgSvc.nginx-vhost-exporter.address}:${toString cfgSvc.nginx-vhost-exporter.port}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.remote_write.integrations.receiver]
            job_name = "integrations/nginx-vts"
            metrics_path = "/status/format/prometheus"
          }

        '';

        varnishCache = optional (cfgSvc.prometheus.exporters ? varnish && cfgSvc.prometheus.exporters.varnish.enable) ''
          // Varnish cache integration components
          prometheus.scrape "integrations_varnish_cache" {
            targets = [{
              __address__ = "${cfgSvc.prometheus.exporters.varnish.listenAddress}:${toString cfgSvc.prometheus.exporters.varnish.port}",
              ${concatStringsSep ", \n" (mapAttrsToList (n: v: "${n} = \"${v}\"") cfg.labels)},
            }]
            forward_to = [prometheus.relabel.integrations_varnish_cache.receiver]
            job_name = "integrations/varnish-cache"
            metrics_path = "${cfgSvc.prometheus.exporters.varnish.telemetryPath}"
          }

          prometheus.relabel "integrations_varnish_cache" {
            forward_to = [prometheus.remote_write.integrations.receiver]
            rule {
              source_labels = ["__name__"]
              regex = "${"^"
            + concatMapStringsSep "|" (s: "${s}") [
              "varnish_backend_beresp_(bodybytes|hdrbytes)"
              "varnish_main_backend_(busy|conn|recycle|req|reuse|unhealthy)"
              "varnish_main_cache_(hit|hitpass|miss)"
              "varnish_main_client_req"
              "varnish_main_n_expired"
              "varnish_main_n_lru_nuked"
              "varnish_main_pools"
              "varnish_main_s_resp_(bodybytes|hdrbytes)"
              "varnish_main_sessions"
              "varnish_main_sessions_total"
              "varnish_main_thread_queue_len"
              "varnish_main_threads"
              "varnish_main_threads_(created|failed|limited)"
              "varnish_sma_g_bytes"
              "varnish_sma_g_space"
            ]
            + "$"}"
              action = "keep"
            }
          }

        '';
      };

      cfgSvc = config.services;
      cfg = config.services.alloy;
    in {
      key = ./profile-grafana-alloy.nix;

      options = {
        services.alloy = {
          enableLiveDebugging = mkOption {
            type = bool;
            default = true;
            description = "Whether to enable live debugging for grafana alloy.";
          };

          extraAlloyConfig = mkOption {
            type = lines;
            default = "";
            description = ''
              Extra configuration appended to the /etc/alloy/config.alloy file prior to formatting.
            '';
          };

          labels = mkOption {
            type = attrsOf str;
            default = {
              instance = name;
              environment = environmentName;
              group = groupName;
            };
            description = "The default set of labels to add to non-default component metrics.";
          };

          logLevel = mkOption {
            type = enum ["debug" "info" "warn" "error"];
            default = "debug";
            description = "The default log level for grafana alloy.";
          };

          prometheusExporterUnixNodeSetCollectors = mkOption {
            type = listOf str;
            default = [
              "boottime"
              "conntrack"
              "cpu"
              "diskstats"
              "filefd"
              "filesystem"
              "loadavg"
              "meminfo"
              "netdev"
              "netstat"
              "os"
              "sockstat"
              "softnet"
              "stat"
              "systemd"
              "time"
              "timex"
              "uname"
              "vmstat"
            ];
            description = "The default set collectors to use for the prometheus unix exporter component.";
          };

          prometheusRelabelAlloyKeepRegex = mkOption {
            type = str;
            default = "^alloy_build.*|alloy_resources.*|prometheus_remote_write_wal_samples_appended_total|prometheus_sd_discovered_targets|process_start_time_seconds|prometheus_target_.*|up$";
            description = "The default keep regex string for the prometheus relabel alloy integration component.";
          };

          prometheusRelabelNodeKeepRegex = mkOption {
            type = str;
            default =
              "^"
              + concatMapStringsSep "|" (s: "${s}") [
                "node_boot_time_seconds"
                "node_context_switches_total"
                "node_cpu_seconds_total"
                "node_disk_io_time_(seconds|weighted_seconds)_total"
                "node_disk_(read|reads|writes|written)_.*"
                "node_filefd_.*"
                "node_filesystem_.*"
                "node_intr_total"
                "node_load([[:digit:]]+)"
                "node_memory_(Active(|_file|_anon)|Inactive(|_file|_anon))_bytes"
                "node_memory_Anon(HugePages|Pages)_bytes"
                "node_memory_(Bounce|Committed_AS|CommitLimit|Dirty|Mapped)_bytes"
                "node_memory_DirectMap(1G|2M|4k)_bytes"
                "node_memory_HugePages_(Free|Rsvd|Surp|Total)"
                "node_memory_Hugepagesize_bytes"
                "node_memory_(Mem(Available|Free|Total)|Buffers|Cached|SwapTotal)_bytes"
                "node_memory_Shmem(|HugPages|PmdMapped)_bytes"
                "node_memory_S(Reclaimable|Unreclaim)_bytes"
                "node_memory_Vmalloc(Chunk|Total|Used)_bytes"
                "node_memory_Writeback(|Tmp)_bytes"
                "node_netstat_Icmp6_(InErrors|InMsgs|OutMsgs)"
                "node_netstat_Icmp_(InErrors|InMsgs|OutMsgs)"
                "node_netstat_IpExt_(InOctets|OutOctets)"
                "node_netstat_TcpExt_(ListenDrops|ListenOverflows|SyncookiesFailed|SyncookiesRecv|SyncookiesSent|TCPOFOQueue|TCPRcvQDrop|TCPSynRetrans|TCPTimeouts)"
                "node_netstat_Tcp_(ActiveOpens|CurrEstab|InErrs|InSegs|OutRsts|OutSegs|PassiveOpens|RetransSegs)"
                "node_netstat_Udp6_(InDatagrams|InErrors|NoPorts|OutDatagrams|RcvbufErrors|SndbufErrors)"
                "node_netstat_Udp_(InDatagrams|InErrors|NoPorts|OutDatagrams|RcvbufErrors|SndbufErrors)"
                "node_netstat_UdpLite_InErrors"
                "node_network_.*"
                "node_nf_conntrack_entries(|_limit)"
                "node_os_info"
                "node_sockstat_(FRAG|FRAG6|RAW|RAW6)_inuse"
                "node_sockstat_sockets_used"
                "node_sockstat_TCP6_inuse"
                "node_sockstat_TCP_(alloc|inuse|mem|orphan|tw)"
                "node_sockstat_(TCP|UDP)_mem_bytes"
                "node_sockstat_UDP_mem"
                "node_sockstat_(UDP|UDP6|UDPLITE|UDPLITE6)_inuse"
                "node_softnet_(dropped|processed|times_squeezed)_total"
                "node_systemd_.*"
                "node_timex_(estimated_error|maxerror|offset)_seconds"
                "node_timex_sync_status"
                "node_time_zone_offset_seconds"
                "node_uname_info"
                "node_vmstat_(pgmajfault|pgfault|pgpgin|pgpgout|pswpin|pswpout|oom_kill)"
              ]
              + "$";
            description = "The default keep regex string for the prometheus relabel alloy node exporter integration component.";
          };

          systemdEnableRestartMetrics = mkOption {
            type = bool;
            default = true;
            description = "Enables service unit metric service_restart_total collection.";
          };

          systemdEnableStartTimeMetrics = mkOption {
            type = bool;
            default = false;
            description = "Enables service unit metric unit_start_time_seconds collection.";
          };

          systemdEnableTaskMetrics = mkOption {
            type = bool;
            default = false;
            description = "Enables service unit tasks metrics unit_tasks_current and unit_tasks_max collection.";
          };

          systemdUnitExclude = mkOption {
            type = str;
            default = ".+\\\\.(automount|device|mount|scope|slice)";
            description = ''
              Regexp of systemd units to exclude.
              Units must both match include and not match exclude to be collected.
            '';
          };

          systemdUnitInclude = mkOption {
            type = str;
            default = "(^cardano.*)|(^metadata.*)|(^nginx.*)|(^smash.*)|(^varnish.*)";
            description = ''
              Regexp of systemd units to include.
              Units must both match include and not match exclude to be collected.
            '';
          };

          useSopsSecrets = mkOption {
            type = bool;
            default = true;
            description = ''
              Whether to use the default configurated sops secrets if true,
              or user deployed secrets if false.

              If false, the following required secrets files, each containing
              one secret indicated by filename and without newline termination,
              will need to be provided to the target machine either by
              additional module code or out of band:

                /run/secrets/grafana-alloy-metrics-url
                /run/secrets/grafana-alloy-metrics-username
                /run/secrets/grafana-alloy-metrics-password
            '';
          };
        };
      };

      config = {
        environment.etc."alloy/config.alloy".source = let
          alloyCfg' =
            toFile "alloy-unformatted.config"
            (
              #
              # Base required component configuration snippets
              #
              alloyComponentCfg.logging
              + alloyComponentCfg.livedebugging
              + alloyComponentCfg.secrets
              + alloyComponentCfg.remoteWrite
              + alloyComponentCfg.alloy
              + alloyComponentCfg.exporter
              #
              # Cardano-parts optional component configuration snippets
              #
              + concatStringsSep "\n" (
                cardanoPartsComponentCfg.blockperf
                ++ cardanoPartsComponentCfg.cardanoCustomMetrics
                ++ cardanoPartsComponentCfg.cardanoDbSync
                ++ cardanoPartsComponentCfg.cardanoFaucet
                ++ cardanoPartsComponentCfg.cardanoNode
                ++ cardanoPartsComponentCfg.cardanoSmash
                ++ cardanoPartsComponentCfg.mithrilSigner
                ++ cardanoPartsComponentCfg.nginxVts
                ++ cardanoPartsComponentCfg.varnishCache
              )
              + cfg.extraAlloyConfig
            );
        in
          (pkgs.runCommandNoCCLocal "alloy.config" {} ''
            ${getExe cfg.package} fmt ${alloyCfg'} > $out
          '')
          .out;

        services.alloy = {
          enable = true;

          extraFlags = [
            "--disable-reporting"
            "--stability.level=experimental"
          ];

          package = inputs'.nixpkgs-unstable.legacyPackages.grafana-alloy;
        };

        systemd.services.alloy = {
          # The alloy collector may error when collecting systemd metrics with a dynamic user.
          # Also, this allows for using non-root systemd process with non-root secrets files.
          serviceConfig = {
            User = "grafana-alloy";
            Group = "grafana-alloy";
            DynamicUser = mkForce false;
          };
        };

        users = {
          groups.grafana-alloy = {};
          users.grafana-alloy = {
            group = "grafana-alloy";
            isSystemUser = true;
          };
        };

        sops.secrets = mkIf cfg.useSopsSecrets (
          mkSopsSecret (mkSopsSecretParams "grafana-alloy-metrics-url")
          // mkSopsSecret (mkSopsSecretParams "grafana-alloy-metrics-username")
          // mkSopsSecret (mkSopsSecretParams "grafana-alloy-metrics-password")
        );
      };
    });
}
