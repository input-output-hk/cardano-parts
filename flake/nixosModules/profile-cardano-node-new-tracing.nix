# nixosModule: profile-cardano-node-new-tracing
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module
#   * This module provides a preview of the new tracing system using cardano-tracer which will soon replace the legacy system
#   * The upstream cardano-node nixos service module should still be imported separately
{
  flake.nixosModules.profile-cardano-node-new-tracing = {
    config,
    pkgs,
    lib,
    name,
    ...
  }: let
    inherit (builtins) fromJSON readFile;
    inherit (lib) mkOption optionalAttrs types;
    inherit (types) anything attrsOf either float ints listOf nullOr oneOf port str;
    inherit (config.cardano-parts.cluster.group.meta) environmentName;
    inherit (perNodeCfg.meta) cardanoNodePrometheusExporterPort hostAddr;
    inherit (perNodeCfg.lib) cardanoLib;
    inherit (cardanoLib.environments.${environmentName}.nodeConfig) ByronGenesisFile;
    inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;

    perNodeCfg = config.cardano-parts.perNode;
    cfg = config.services.cardano-tracer;
  in {
    # Leave the import of the upstream cardano-node service for
    # cardano-parts consuming repos so that service import can be customized.
    #
    # Unfortunately, we can't customize the import based on
    # perNode nixos options as this leads to infinite recursion.
    #
    # imports = [
    #   (
    #     # Existing tracer service requires a pkgs with commonLib defined in the cardano-node repo flake overlay.
    #     # We'll import it through flake-compat so we don't need a full flake input just for obtaining commonLib.
    #     import
    #     config.cardano-parts.cluster.groups.default.meta.cardano-tracer-service
    #     (import
    #       "${config.cardano-parts.cluster.groups.default.meta.cardano-node-service}/../../default.nix" {inherit system;})
    #     .legacyPackages
    #     .${system}
    #   )
    # ];

    options = {
      services = {
        cardano-tracer = {
          # Upstream predefined cardano-tracer service options are included in
          # the comments below. These options do not provide enough flexibility
          # in creating a tracer config file for our use case, so the
          # additional options declared below are used in instead and/or in
          # addition.  The upstream cardano-tracer nixos service will be
          # rewritten in the near future.

          # networkMagic    = opt    int 764824073   "Network magic (764824073 for Cardano mainnet).";
          # acceptingSocket = mayOpt str             "Socket path: as acceptor.";
          # connectToSocket = mayOpt str             "Socket path: connect to.";
          # logRoot         = opt    str null        "Log storage root directory.";
          # rotation        = opt    attrs {}        "Log rotation overrides: see cardano-tracer documentation.";
          # RTView          = opt    attrs {}        "RTView config overrides: see cardano-tracer documentation.";
          # ekgPortBase     = opt    int 3100        "EKG port base.";
          # ekgRequestFreq  = opt    int 1           "EKG request frequency";
          # prometheus      = opt    attrs {}        "Prometheus overrides: see cardano-tracer documentation.";
          # resourceFreq    = mayOpt int             "Frequency (1/ms) for tracing resource usage.";
          # extraCliArgs    = opt    (listOf str) [] "Extra CLI args.";

          hasEKG = mkOption {
            type = nullOr (listOf (attrsOf (either str port)));
            default = [
              # Preserve legacy EKG binding unless we have a reason to switch.
              # Let's see how the updated nixos node service chooses for defaults.
              {
                epHost = "127.0.0.1";
                epPort = 12788;
              }
              {
                epHost = "127.0.0.1";
                epPort = 12789;
              }
            ];
          };

          hasPrometheus = mkOption {
            type = nullOr (attrsOf (either str port));
            # Preserve legacy prometheus binding unless we have a reason to switch
            # Let's see what the updated nixos node service chooses for defaults.
            default = {
              epHost = hostAddr;
              epPort = cardanoNodePrometheusExporterPort;
            };
          };

          # As of node release 9.1 this option has no effect unless node was
          # built with `-f +rtview`.
          # Ref:
          # https://github.com/IntersectMBO/cardano-node/pull/5846
          hasRTView = mkOption {
            type = nullOr (attrsOf (either str port));
            default = {
              epHost = "127.0.0.1";
              epPort = 3300;
            };
          };

          logging = mkOption {
            # A cardano-tracer error will be thrown if the logging list is
            # empty or not included.
            type = listOf (attrsOf str);
            default = [
              {
                logFormat = "ForHuman";
                # logFormat = "ForMachine";

                # Selecting `JournalMode` seems to force `ForMachine` logFormat
                # even if `ForHuman` is selected.
                logMode = "JournalMode";
                # logMode = "FileMode";

                # /dev/null seems to work but will limit RTView log review capability.
                # logRoot = "/dev/null";
                logRoot = "/tmp/cardano-node-logs";
              }
            ];
          };

          network = mkOption {
            type = attrsOf str;
            default = {
              contents = "/tmp/forwarder.sock";
              tag = "AcceptAt";
            };
          };

          nodeDefaultTraceOptions = mkOption {
            type = nullOr (attrsOf anything);
            # Default node trace options for the `""` backend
            default = {
              severity = "Notice";
              detail = "DNormal";
              backends = [
                # This results in journald output for the cardano-node service,
                # like we would normally expect. This will, however, create
                # duplicate logging if the tracer service resides on the same
                # machine as the node service.
                #
                # In general, the "human" logging which appears in the
                # cardano-node service is more human legible than the
                # "ForHuman" node logging that appears in cardano-tracer for
                # the same log events.
                "Stdout HumanFormatColoured"
                # "Stdout HumanFormatUncoloured"
                # "Stdout MachineFormat"

                # Leave EKG disabled in node as tracer now generates this as well.
                # "EKGBackend"

                # Forward to tracer.
                "Forwarder"
              ];
            };
          };

          nodeExtraTraceOptions = mkOption {
            type = nullOr (attrsOf anything);
            default = {
              # Reference: https://github.com/IntersectMBO/cardano-node/blob/main/nix/workbench/service/tracing.nix
              #
              # This is a list with all tracers, adopted to the on and off
              # state in old tracing.
              "BlockFetch.Client".severity = "Debug";
              "BlockFetch.Decision".severity = "Notice";
              "BlockFetch.Remote".severity = "Notice";
              "BlockFetch.Remote.Serialised".severity = "Notice";
              "BlockFetch.Server".severity = "Debug";
              "BlockchainTime".severity = "Notice";
              "ChainDB".severity = "Debug";
              "ChainDB.ReplayBlock.LedgerReplay".severity = "Notice";
              "ChainSync.Client".severity = "Debug";
              "ChainSync.Local".severity = "Notice";
              "ChainSync.Remote".severity = "Notice";
              "ChainSync.Remote.Serialised".severity = "Notice";
              "ChainSync.ServerBlock".severity = "Notice";
              "ChainSync.ServerHeader".severity = "Debug";
              "Forge.Loop".severity = "Debug";
              "Forge.StateInfo".severity = "Debug";
              "Mempool".severity = "Debug";
              "Net".severity = "Notice";
              "Net.AcceptPolicy".severity = "Debug";
              "Net.ConnectionManager.Local".severity = "Debug";
              "Net.ConnectionManager.Remote".severity = "Debug";
              "Net.DNSResolver".severity = "Notice";
              "Net.ErrorPolicy.Local".severity = "Debug";
              "Net.ErrorPolicy.Remote".severity = "Debug";
              "Net.Handshake.Local".severity = "Debug";
              "Net.Handshake.Remote".severity = "Debug";
              "Net.InboundGovernor.Local".severity = "Debug";
              "Net.InboundGovernor.Remote".severity = "Debug";
              "Net.InboundGovernor.Transition".severity = "Debug";
              "Net.Mux.Local".severity = "Notice";
              "Net.Mux.Remote".severity = "Notice";
              "Net.PeerSelection.Actions".severity = "Debug";
              "Net.PeerSelection.Counters".detail = "DMinimal";
              "Net.PeerSelection.Counters".severity = "Debug";
              "Net.PeerSelection.Initiator".severity = "Notice";
              "Net.PeerSelection.Responder".severity = "Notice";
              "Net.PeerSelection.Selection".severity = "Debug";
              "Net.Peers.Ledger".severity = "Debug";
              "Net.Peers.List".severity = "Notice";
              "Net.Peers.LocalRoot".severity = "Debug";
              "Net.Peers.PublicRoot".severity = "Debug";
              "Net.Server.Local".severity = "Debug";
              "Net.Server.Remote".severity = "Debug";
              "Net.Subscription.DNS".severity = "Debug";
              "Net.Subscription.IP".severity = "Debug";
              "NodeState".severity = "Notice";
              "Resources".severity = "Debug";
              "Shutdown".severity = "Notice";
              "Startup".severity = "Notice";
              "Startup.DiffusionInit".severity = "Debug";
              "StateQueryServer".severity = "Notice";
              "TxSubmission.Local".severity = "Notice";
              "TxSubmission.LocalServer".severity = "Notice";
              "TxSubmission.MonitorClient".severity = "Notice";
              "TxSubmission.Remote".severity = "Notice";
              "TxSubmission.TxInbound".severity = "Debug";
              "TxSubmission.TxOutbound".severity = "Notice";
              "Version.NodeVersion".severity = "Info";

              # These messages are UTxO-HD specific. On a regular node, the
              # tracing system might warn at startup about config
              # inconsistencies (as those tracers do not exist). This warning
              # is expected, and can be safely ignored. Silencing the tracers
              # below aims at having a comparable log line rates (messages per
              # second) on UTxO-HD and regular nodes.
              "ChainDB.LedgerEvent.Forker".severity = "Silence";
              "Mempool.MempoolAttemptAdd".severity = "Silence";
              "Mempool.MempoolAttemptingSync".severity = "Silence";
              "Mempool.MempoolLedgerFound".severity = "Silence";
              "Mempool.MempoolLedgerNotFound".severity = "Silence";
              "Mempool.MempoolSyncDone".severity = "Silence";
              "Mempool.MempoolSyncNotNeeded".severity = "Silence";

              # Enable this to investigate tx validation errors, e.g. fee to
              # small for Plutus script txns comes with too much overhead to be
              # the default for benchmarks
              # "Mempool.RejectedTx".detail = "DDetailed";
            };
          };

          # The upstream service already declares option `rotation`
          rotationCfg = mkOption {
            type = attrsOf ints.positive;
            default = {
              rpFrequencySecs = 15;
              rpKeepFilesNum = 10;
              rpLogLimitBytes = 1000000000;
              rpMaxAgeHours = 24;
            };
          };

          totalMaxHeapSizeMiB = mkOption {
            type = oneOf [ints.positive float];
            default = 256;
          };
        };
      };
    };

    config = {
      services.cardano-tracer = {
        enable = true;
        package = perNodeCfg.pkgs.cardano-tracer;
        executable = lib.getExe perNodeCfg.pkgs.cardano-tracer;
        acceptingSocket = "/tmp/forwarder.sock";
        extraCliArgs = ["+RTS" "-M${toString cfg.totalMaxHeapSizeMiB}M" "-RTS"];

        configFile = builtins.toFile "cardano-tracer-config.json" (
          builtins.toJSON ({
              inherit (cfg) logging network;

              networkMagic = protocolMagic;

              resourceFreq = null;

              rotation = cfg.rotationCfg;
            }
            // optionalAttrs (cfg.hasEKG != null) {
              # EKG interface uses the https scheme.
              inherit (cfg) ekgRequestFreq hasEKG;
            }
            // optionalAttrs (cfg.hasPrometheus != null) {
              # Metrics exporter with a scrape path of:
              # http://$epHost:$epPort/$TraceOptionNodeName
              inherit (cfg) hasPrometheus;
            }
            // optionalAttrs (cfg.hasRTView != null) {
              # The real time viewer uses the https scheme.
              inherit (cfg) hasRTView;
            })
        );
      };

      systemd.services.cardano-tracer = {
        wantedBy = ["multi-user.target"];
        environment.HOME = "/var/lib/cardano-tracer";
        serviceConfig = {
          MemoryMax = "${toString (1.15 * cfg.totalMaxHeapSizeMiB)}M";
          LimitNOFILE = "65535";

          StateDirectory = "cardano-tracer";
          WorkingDirectory = "/var/lib/cardano-tracer";
        };
      };

      services.cardano-node = {
        tracerSocketPathConnect = "/tmp/forwarder.sock";

        # This removes most of the old tracing system config.
        # It will only leave a minSeverity = "Critical" for the legacy system active.
        useLegacyTracing = false;

        # This appears to do nothing.
        withCardanoTracer = true;

        extraNodeConfig = {
          # This option is what enables the new tracing/metrics system.
          UseTraceDispatcher = true;

          # Default options; further customization can be added per tracer.
          TraceOptions =
            {
              "" = optionalAttrs (cfg.nodeDefaultTraceOptions != null) cfg.nodeDefaultTraceOptions;
            }
            // optionalAttrs (cfg.nodeExtraTraceOptions != null) cfg.nodeExtraTraceOptions;
        };

        extraNodeInstanceConfig = i: {
          # This is important to set, otherwise tracer log files and RTView will get an ugly name.
          TraceOptionNodeName =
            if (i == 0)
            then name
            else "${name}-${toString i}";
        };
      };
    };
  };
}
