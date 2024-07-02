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
    inherit (lib) mkOption types;
    inherit (types) float ints oneOf;
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

        # With the current tracer service, setting these alone is not enough as
        # the config is hardcoded to use `ForMachine` output and RTView is not
        # included.
        #
        # So if we want more customization, we need to generate our own full config.
        #
        # logRoot = "/tmp/logs";
        # networkMagic = protocolMagic;

        configFile = builtins.toFile "cardano-tracer-config.json" (builtins.toJSON {
          ekgRequestFreq = 1;

          # EKG interface at https.
          hasEKG = [
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

          # Metrics exporter with a scrape path of:
          # http://$epHost:$epPort/$TraceOptionNodeName
          hasPrometheus = {
            # Preserve legacy prometheus binding unless we have a reason to switch
            # Let's see how the updated nixos node service chooses for defaults.
            epHost = hostAddr;
            epPort = cardanoNodePrometheusExporterPort;
          };

          # Real time viewer at https.
          hasRTView = {
            epHost = "127.0.0.1";
            epPort = 3300;
          };

          # A cardano-tracer error will be thrown if the logging list is empty or
          # not included.
          logging = [
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

          network = {
            contents = "/tmp/forwarder.sock";
            tag = "AcceptAt";
          };

          networkMagic = protocolMagic;
          resourceFreq = null;

          rotation = {
            rpFrequencySecs = 15;
            rpKeepFilesNum = 10;
            rpLogLimitBytes = 1000000000;
            rpMaxAgeHours = 24;
          };
        });
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
          TraceOptions = {
            "" = {
              severity = "Notice";
              detail = "DNormal";
              backends = [
                # This results in journald output for the service, like we would normally expect.
                "Stdout HumanFormatColoured"
                # "Stdout HumanFormatUncoloured"
                # "Stdout MachineFormat"

                # Leave EKG disabled in node as tracer now generates this as well
                # "EKGBackend"

                # Forward to tracer
                "Forwarder"
              ];
            };
          };
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
