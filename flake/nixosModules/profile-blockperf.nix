# nixosModule: profile-blockperf
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.blockperf.amazonCa
#   config.services.blockperf.clientCert
#   config.services.blockperf.clientKey
#   config.services.blockperf.logFile
#   config.services.blockperf.logKeepFilesNum
#   config.services.blockperf.logLimitBytes
#   config.services.blockperf.logMaxAgeHours
#   config.services.blockperf.maskedDnsList
#   config.services.blockperf.maskedIpList
#   config.services.blockperf.name
#   config.services.blockperf.package
#   config.services.blockperf.port
#   config.services.blockperf.secretsPathPrefix
#   config.services.blockperf.useSopsSecrets
#
# Tips:
#   * This is an add-on to the profile-cardano-node-group nixos service module
#   * This module modifies runs blockperf and modifies the cardano-node service to do so
#   * The profile-cardano-node-group nixos service module should still be imported separately
flake: {
  flake.nixosModules.profile-blockperf = {
    config,
    lib,
    pkgs,
    name,
    ...
  }: let
    inherit (builtins) concatStringsSep head;
    inherit (lib) escapeShellArgs hasSuffix getExe mkIf mkOption optional optionalString splitString;
    inherit (lib.types) bool int listOf nullOr package port str;
    inherit (groupCfg) groupName groupFlake;
    inherit (opsLib) mkSopsSecret;

    groupCfg = config.cardano-parts.cluster.group;
    groupOutPath = groupFlake.self.outPath;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

    mkSopsSecretParams = secretName: keyName: {
      inherit keyName groupOutPath groupName name secretName;
      fileOwner = "cardano-node";
      fileGroup = "cardano-node";
      pathPrefix =
        if hasSuffix "/" cfg.secretsPathPrefix
        then cfg.secretsPathPrefix
        else cfg.secretsPathPrefix + "/";
      restartUnits = ["blockPerf.service"];
    };

    sopsPath = name: config.sops.secrets.${name}.path;

    cfg = config.services.blockperf;
    cfgNode = config.services.cardano-node;
  in {
    key = ./profile-blockperf.nix;

    options.services.blockperf = {
      amazonCa = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          The filename of the local encrypted amazon CA in PEM format.

          Path to the Amazon CA file in PEM format, sourced from:
            https://www.amazontrust.com/repository/AmazonRootCA1.pem
        '';
      };

      clientCert = mkOption {
        type = nullOr str;
        default = null;
        description = "The filename of the local encrypted client certificate.";
      };

      clientKey = mkOption {
        type = nullOr str;
        default = null;
        description = "The filename of the local encrypted client key.";
      };

      debugBlockperf = mkOption {
        type = bool;
        default = false;
        description = "Whether or not to enable blockperf debug logging.";
      };

      debugScript = mkOption {
        type = bool;
        default = false;
        description = "Whether or not to enable systemd script debugging.";
      };

      maskedDnsList = mkOption {
        type = listOf str;
        default = [];
        description = ''
          The blockperf client DNS name list to be masked.

          The DNS names in this list will first be resolved to IPs
          and then prevented from being leaked in the blockperf service.

          Add block producer DNS to this list if the IPs are not available to declare.
        '';
      };

      maskedIpList = mkOption {
        type = listOf str;
        default = [];
        description = ''
          The blockperf client IP address list to be masked.

          This will prevent these IPs from being leaked in the blockperf service.

          Add block producer IPs to this list.
        '';
      };

      name = mkOption {
        type = nullOr str;
        default = null;
        description = "The blockperf client identifier provided by Cardano Foundation.";
      };

      package = mkOption {
        type = package;
        default = config.cardano-parts.perNode.pkgs.blockperf;
        description = "The default blockperf package.";
      };

      port = mkOption {
        type = nullOr port;
        default = 8082;
        description = "The default blockperf prometheus port. Set to null to disable metrics.";
      };

      publish = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to enable publishing of block performance to Cardano Foundation.

          For testnets and throwaway machines, it may be desirable to set this
          false and only collect block performance prometheus metrics for
          internal analysis.
        '';
      };

      logFile = mkOption {
        type = str;
        default =
          if cfgNode.useLegacyTracing
          then "${cfgNode.stateDir 0}/blockperf/node.json"
          else "${cfgNode.stateDir 0}/blockperf/${name}/node.json";
        description = "The full path and file name of the node log file which blockperf consumes.";
      };

      logLimitBytes = mkOption {
        type = int;
        default = 5 * 1024 * 1024;
        description = ''
          The rpLogLimitBytes for the node log file legacy scribe rotation.
          See: https://github.com/input-output-hk/iohk-monitoring-framework/wiki/Log-rotation
        '';
      };

      logKeepFilesNum = mkOption {
        type = int;
        default = 10;
        description = ''
          The rpKeepFilesNum for the node log file legacy scribe rotation.
          See: https://github.com/input-output-hk/iohk-monitoring-framework/wiki/Log-rotation
        '';
      };

      logMaxAgeHours = mkOption {
        type = int;
        default = 24;
        description = ''
          The rpMaxAgeHours for the node log file legacy scribe rotation.
          See: https://github.com/input-output-hk/iohk-monitoring-framework/wiki/Log-rotation
        '';
      };

      secretsPathPrefix = mkOption {
        type = str;
        default = "${groupOutPath}/secrets/monitoring";
        description = ''
          The path where the local encrypted secrets files will be obtained
          from if useSopsSecrets is true.
        '';
      };

      useSopsSecrets = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to use the default configurated sops secrets if true,
          or user deployed secrets if false.

          If false, the following secrets files, each containing one secret
          indicated by filename, will need to be provided to the target machine
          either by additional module code or out of band:

            /run/secrets/blockperf-amazon-ca.pem
            /run/secrets/blockperf-client-cert.pem
            /run/secrets/blockperf-client.key
        '';
      };
    };

    # Blockperf does not yet work with the new tracing system
    config = {
      environment.systemPackages = [cfg.package];

      services = {
        cardano-node = {
          extraNodeInstanceConfig = _:
            if cfgNode.useLegacyTracing
            then {
              TraceChainSyncClient = true;
              TraceBlockFetchClient = true;

              # We need to redeclare the standard setup in the list along
              # with the new blockperf config because:
              #   * cfgNode.extraNodeConfig won't merge or replace lists
              #   * cfgNode.extraNodeInstanceConfig replaces lists
              defaultScribes = [
                # Standard scribe
                ["JournalSK" "cardano"]

                # Blockperf required
                ["FileSK" cfg.logFile]
              ];

              setupScribes = [
                # Standard scribe
                {
                  scFormat = "ScText";
                  scKind = "JournalSK";
                  scName = "cardano";
                }

                # Blockperf required
                {
                  scFormat = "ScJson";
                  scKind = "FileSK";
                  scName = cfg.logFile;
                  scRotation = {
                    rpLogLimitBytes = cfg.logLimitBytes;
                    rpKeepFilesNum = cfg.logKeepFilesNum;
                    rpMaxAgeHours = cfg.logMaxAgeHours;
                  };
                }
              ];
            }
            else {
              TraceOptions = {
                "BlockFetch.Client.SendFetchRequest" = {
                  details = "DNormal";
                  maxFrequency = 0.0;
                  severity = "Info";
                };
                "BlockFetch.Client.CompletedBlockFetch" = {
                  details = "DNormal";
                  maxFrequency = 0.0;
                  severity = "Info";
                };
                "ChainDb.AddBlockEvent.AddedToCurrentChain" = {
                  details = "DNormal";
                  maxFrequency = 0.0;
                  severity = "Info";
                };
                "ChainDb.AddBlockEvent.SwitchedToAFork" = {
                  details = "DNormal";
                  maxFrequency = 0.0;
                  severity = "Info";
                };
                "ChainSync.Client.DownloadedHeader" = {
                  details = "DNormal";
                  maxFrequency = 0.0;
                  severity = "Info";
                };
              };
            };
        };

        cardano-tracer = {
          logging = [
            {
              logFormat = "ForMachine";
              logMode = "FileMode";
              logRoot = head (splitString "/${name}" cfg.logFile);
            }
          ];
        };
      };

      # The blockperf systemd service name cannot contain the string "blockperf"
      # or the bin utility will think it is already running
      systemd.services.blockPerf = {
        # Ensure blockperf can also query from /etc/hosts properly if dnsmasq service is enabled
        after = ["cardano-node.service"] ++ optional config.services.dnsmasq.enable "dnsmasq.service";
        wants = ["cardano-node.service"] ++ optional config.services.dnsmasq.enable "dnsmasq.service";
        partOf = ["cardano-node.service"];
        wantedBy = ["cardano-node.service"];

        # Allow up to 10 failures with 30 second restarts in a 15 minute window
        # before entering failure state and alerting
        startLimitBurst = 10;
        startLimitIntervalSec = 900;

        environment = {
          # Whether to enable systemd script debugging
          DEBUG = mkIf cfg.debugScript "True";

          # Whether to publish to CF upstream
          BLOCKPERF_LEGACY_TRACING =
            if cfgNode.useLegacyTracing
            then "True"
            else "False";

          # Whether to publish to CF upstream
          BLOCKPERF_PUBLISH =
            if cfg.publish
            then "True"
            else "False";

          # The port to publish metrics to
          BLOCKPERF_METRICS_PORT =
            if cfg.port == null
            then "disabled"
            else toString cfg.port;

          # Path to the cardano-node blockperf log file
          BLOCKPERF_NODE_LOGFILE = cfg.logFile;

          # The client identifier; will be given to you with the certificates
          BLOCKPERF_NAME =
            if cfg.name == null
            then ""
            else cfg.name;

          # Path to the client certificate file
          BLOCKPERF_CLIENT_CERT =
            if cfg.clientCert == null
            then ""
            else if cfg.useSopsSecrets
            then sopsPath "blockperf-client-cert.pem"
            else "/run/secrets/blockperf-client-cert.pem";

          # Path to the client key file
          BLOCKPERF_CLIENT_KEY =
            if cfg.clientKey == null
            then ""
            else if cfg.useSopsSecrets
            then sopsPath "blockperf-client.key"
            else "/run/secrets/blockperf-client.key";

          # Path to the Amazon CA file in PEM format, find it here:
          #   https://www.amazontrust.com/repository/AmazonRootCA1.pem
          BLOCKPERF_AMAZON_CA =
            if cfg.amazonCa == null
            then ""
            else if cfg.useSopsSecrets
            then sopsPath "blockperf-amazon-ca.pem"
            else "/run/secrets/blockperf-amazon-ca.pem";
        };

        serviceConfig = {
          ExecStart = getExe (pkgs.writeShellApplication {
            # Must not be named `blockperf` for the same reason the systemd service name cannot
            name = "blockPerf";
            runtimeInputs = with pkgs; [cfg.package dig gnugrep];
            text = ''
              set -euo pipefail

              [ -n "''${DEBUG:-}" ] && set -x

              # Set the node config path
              #
              # The nixos service does not make the config file accessible,
              # so we either need to regenerate it completely, or parse it
              # out of the systemd unit
              START_SCRIPT=$(grep -oP "ExecStart=\K([^ ]+)" /etc/systemd/system/cardano-node.service)
              NODE_CONFIG=$(grep -oP '   echo "--config \K(.*\.json)' "$START_SCRIPT")
              export BLOCKPERF_NODE_CONFIG="$NODE_CONFIG"

              # Set our public IP preferably using the node's ip-module ip or a
              # generic resolver that is cloud/platform independent.
              PUBLIC_IP=${
                if (config.ips.publicIpv4 or config.ips.publicIpv6 or "" != "")
                then "\"${config.ips.publicIpv4 or config.ips.publicIpv6}\""
                else "$(dig -4 +short @resolver1.opendns.com myip.opendns.com)"
              }
              export BLOCKPERF_RELAY_PUBLIC_IP="$PUBLIC_IP"

              MASKED="${concatStringsSep "," cfg.maskedIpList}"
              for DNS in ${escapeShellArgs cfg.maskedDnsList}; do
                IP=$(dig +short "$DNS" ANY)
                if [ "$IP" != "" ]; then
                  MASKED+=",$IP"
                else
                  echo "ERROR: Unable to resolve masked dns address: $DNS"
                  exit 1
                fi
              done

              # Remove a leading comma if present
              MASKED="''${MASKED/#,}"

              BLOCKPERF_MASKED_ADDRESSES="$MASKED"
              export BLOCKPERF_MASKED_ADDRESSES

              echo "Blockperf legacy tracing is: ${
                if cfgNode.useLegacyTracing
                then "Enabled"
                else "Disabled"
              }"
              echo "Blockperf publishing is: ${
                if cfg.publish
                then "Enabled"
                else "Disabled"
              }"
              echo "Blockperf machine Amazon CA: $BLOCKPERF_AMAZON_CA"
              echo "Blockperf machine client cert: $BLOCKPERF_CLIENT_CERT"
              echo "Blockperf machine client key: $BLOCKPERF_CLIENT_KEY"
              echo -e "Blockperf machine masked ips:\n  ${concatStringsSep "\n  " cfg.maskedIpList}\n"
              echo -e "Blockperf machine masked dns (to be resolved):\n  ${concatStringsSep "\n  " cfg.maskedDnsList}\n"
              echo -e "Blockperf machine masked addresses string (resolved):\n  $BLOCKPERF_MASKED_ADDRESSES"
              echo "Blockperf metrics port: $BLOCKPERF_METRICS_PORT"
              echo "Starting blockperf..."
              blockperf run ${optionalString cfg.debugBlockperf "--debug"}
            '';
          });

          # Ensure quick restarts on any condition
          Restart = "always";
          RestartSec = 30;
          KillSignal = "SIGINT";
        };
      };

      users.users.cardano-node.extraGroups = ["keys"];

      sops.secrets =
        mkIf cfg.useSopsSecrets
        (mkSopsSecret (mkSopsSecretParams "blockperf-client-cert.pem" cfg.clientCert)
          // mkSopsSecret (mkSopsSecretParams "blockperf-client.key" cfg.clientKey)
          // mkSopsSecret (mkSopsSecretParams "blockperf-amazon-ca.pem" cfg.amazonCa));

      assertions = [
        {
          assertion = cfgNode.instances == 1;
          message = ''The nixos blockperf profile does not currently work with multiple cardano-node instances per machine.'';
        }
      ];
    };
  };
}
