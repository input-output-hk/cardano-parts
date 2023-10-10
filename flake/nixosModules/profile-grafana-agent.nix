# nixosModule: profile-grafana-agent
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
{
  flake.nixosModules.profile-grafana-agent = {
    config,
    lib,
    name,
    ...
  }:
    with builtins;
    with lib; let
      inherit (config.cardano-parts.perNode.meta) cardanoDbSyncPrometheusExporterPort cardanoNodePrometheusExporterPort hostAddr;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) environmentName;

      groupCfg = config.cardano-parts.cluster.group;
      groupOutPath = groupFlake.self.outPath;

      pathPrefix = "${groupOutPath}/secrets/monitoring/";
      trimStorePrefix = path: last (split "/nix/store/[^/]+/" path);
      verboseTrace = key: traceVerbose ("${name}: using " + (trimStorePrefix key));

      mkSopsSecret = secretsFile: {
        ${secretsFile} = verboseTrace (pathPrefix + secretsFile + ".enc") {
          sopsFile = pathPrefix + secretsFile + ".enc";
        };
      };

      cfgSvc = config.services;
    in {
      systemd.services.grafana-agent = {
        after = ["sops-secrets.service"];
        wants = ["sops-secrets.service"];
      };

      sops.secrets =
        mkSopsSecret "grafana-agent-metrics-url"
        // mkSopsSecret "grafana-agent-metrics-username"
        // mkSopsSecret "grafana-agent-metrics-password";

      services.grafana-agent = {
        enable = true;

        credentials = let
          sopsPath = name: config.sops.secrets.${name}.path;
        in {
          # Loaded as env vars
          METRICS_REMOTE_WRITE_URL = sopsPath "grafana-agent-metrics-url";
          METRICS_REMOTE_WRITE_USERNAME = sopsPath "grafana-agent-metrics-username";

          # Loaded as files
          metrics_remote_write_password = sopsPath "grafana-agent-metrics-password";
        };

        extraFlags = [
          "-disable-reporting"
        ];

        settings = let
          metrics-client = {
            basic_auth = {
              password_file = "\${CREDENTIALS_DIRECTORY}/metrics_remote_write_password";
              username = "\${METRICS_REMOTE_WRITE_USERNAME}";
            };
            url = "\${METRICS_REMOTE_WRITE_URL}";
          };

          relabelConfig-agent_hostname-instance = [
            {
              action = "replace";
              source_labels = ["agent_hostname"];
              target_label = "instance";
            }
            {
              action = "labeldrop";
              regex = "^agent_hostname$";
            }
          ];
        in {
          integrations = {
            agent = {
              enabled = true;
              metric_relabel_configs = [
                {
                  action = "keep";
                  regex = "^prometheus_target_.*|prometheus_sd_discovered_targets|agent_build.*|agent_wal_samples_appended_total|process_start_time_seconds$";
                  source_labels = ["__name__"];
                }
              ];

              relabel_configs =
                relabelConfig-agent_hostname-instance
                ++ [
                  {
                    action = "replace";
                    replacement = "integrations/agent-check";
                    target_label = "job";
                  }
                ];
            };

            node_exporter = {
              set_collectors = [
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
                "time"
                "timex"
                "uname"
                "vmstat"
              ];

              relabel_configs = relabelConfig-agent_hostname-instance;

              metric_relabel_configs = [
                {
                  action = "keep";
                  source_labels = ["__name__"];
                  regex =
                    "^"
                    + concatMapStringsSep "|" (s: "(${s})") [
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
                      "node_netstat_TcpExt_(ListenDrops|ListenOverflows|TCPSynRetrans)"
                      "node_netstat_Tcp_(InErrs|InSegs|OutRsts|OutSegs|RetransSegs)"
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
                      "node_timex_(estimated_error|maxerror|offset)_seconds"
                      "node_timex_sync_status"
                      "node_time_zone_offset_seconds"
                      "node_uname_info"
                      "node_vmstat_(pgmajfault|pgfault|pgpgin|pgpgout|pswpin|pswpout|oom_kill)"
                    ]
                    + "$";
                }
                {
                  action = "drop";
                  source_labels = ["__name__"];
                  regex = "^node_filesystem_readonly$";
                }
                {
                  # filesystem collector
                  action = "keep";
                  source_labels = ["mountpoint"];
                  regex = "^|/|/boot|/state|/home|/nix$";
                }
                {
                  # cpu collector
                  action = "keep";
                  source_labels = ["mode"];
                  regex = "^|system|user|iowait|steal|idle$";
                }
              ];
            };

            prometheus_remote_write = [metrics-client];
          };

          metrics = {
            configs = [
              {
                name = "integrations";
                remote_write = [metrics-client];

                scrape_configs = let
                  labels = {
                    instance = name;
                    environment = environmentName;
                    group = groupName;
                  };
                in [
                  (mkIf (cfgSvc ? cardano-db-sync && cfgSvc.cardano-db-sync.enable) {
                    job_name = "integrations/cardano-db-sync";
                    metrics_path = "/";
                    static_configs = [
                      {
                        inherit labels;
                        targets = ["${hostAddr}:${toString cardanoDbSyncPrometheusExporterPort}"];
                      }
                    ];
                  })
                  (mkIf (cfgSvc ? cardano-node && cfgSvc.cardano-node.enable) {
                    job_name = "integrations/cardano-node";
                    metrics_path = "/metrics";
                    static_configs = [
                      {
                        inherit labels;
                        targets = ["${hostAddr}:${toString cardanoNodePrometheusExporterPort}"];
                      }
                    ];
                  })
                  (mkIf (cfgSvc ? cardano-smash) {
                    job_name = "integrations/cardano-smash";
                    metrics_path = "/";
                    static_configs = [
                      {
                        inherit labels;
                        targets = ["${hostAddr}:${toString cfgSvc.cardano-smash.registeredRelaysExporterPort}"];
                      }
                    ];
                  })
                  (mkIf (cfgSvc.nginx ? vhostExporterEnable && cfgSvc.nginx.vhostExporterEnable) {
                    job_name = "integrations/nginx-vts";
                    metrics_path = "/status/format/prometheus";
                    static_configs = [
                      {
                        inherit labels;
                        targets = ["${cfgSvc.nginx.vhostExporterAddress}:${toString cfgSvc.nginx.vhostExporterPort}"];
                      }
                    ];
                  })
                  (mkIf (cfgSvc.prometheus.exporters ? varnish && cfgSvc.prometheus.exporters.varnish.enable) {
                    job_name = "integrations/varnish-cache";
                    metrics_path = cfgSvc.prometheus.exporters.varnish.telemetryPath;
                    metric_relabel_configs = [
                      {
                        action = "keep";
                        regex =
                          "^"
                          + concatMapStringsSep "|" (s: "(${s})") [
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
                          + "$";
                        source_labels = ["__name__"];
                      }
                    ];
                    static_configs = [
                      {
                        inherit labels;
                        targets = ["${cfgSvc.prometheus.exporters.varnish.listenAddress}:${toString cfgSvc.prometheus.exporters.varnish.port}"];
                      }
                    ];
                  })
                ];
              }
            ];
            global.scrape_interval = "1m";
            wal_directory = "\${STATE_DIRECTORY}/grafana-agent-wal";
          };
        };
      };
    };
}
