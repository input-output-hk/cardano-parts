# nixosModule: profile-blockperf
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
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
    ...
  }: let
    inherit (lib) hasSuffix mkOption;
    inherit (lib.types) int package str;
    inherit (groupCfg) groupName groupFlake;
    inherit (opsLib) mkSopsSecret;

    groupCfg = config.cardano-parts.cluster.group;
    groupOutPath = groupFlake.self.outPath;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

    mkSopsSecretParams = secretName: keyName: {
      inherit keyName groupOutPath groupName secretName;
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
    options.services.blockperf = {
      blockperfName = mkOption {
        type = str;
        default = null;
        description = "The blockperf client identifier provided by Cardano Foundation.";
      };

      blockperfClientCert = mkOption {
        type = str;
        default = null;
        description = "The filename of the local encrypted client certificate.";
      };

      blockperfClientKey = mkOption {
        type = str;
        default = null;
        description = "The filename of the local encrypted client key.";
      };

      blockperfAmazonCA = mkOption {
        type = str;
        default = "blockperf-amazon-ca.pem.enc";
        description = ''
          The filename of the local encrypte amazon CA in PEM format

          Path to the Amazon CA file in PEM format, sourced from:
            https://www.amazontrust.com/repository/AmazonRootCA1.pem
        '';
      };

      package = mkOption {
        type = package;
        default = config.cardano-parts.perNode.pkgs.blockperf;
        description = "The default blockperf package";
      };

      nodeLogFile = mkOption {
        type = str;
        default = "${cfgNode.stateDir 0}/blockperf/node.json";
        description = "The full path and file name of the node log file which blockperf consumes.";
      };

      nodeLogLimitBytes = mkOption {
        type = int;
        default = 5 * 1024 * 1024;
        description = ''
          The rpLogLimitBytes for the node log file legacy scribe rotation.
          See: https://github.com/input-output-hk/iohk-monitoring-framework/wiki/Log-rotation
        '';
      };

      nodeLogKeepFilesNum = mkOption {
        type = int;
        default = 10;
        description = ''
          The rpKeepFilesNum for the node log file legacy scribe rotation.
          See: https://github.com/input-output-hk/iohk-monitoring-framework/wiki/Log-rotation
        '';
      };

      nodeLogMaxAgeHours = mkOption {
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
        description = "The path where the local encrypted secrets files will be obtained from.";
      };
    };

    config = {
      environment.systemPackages = [cfg.package];

      services.cardano-node = {
        extraNodeInstanceConfig = _: {
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
            ["FileSK" cfg.nodeLogFile]
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
              scName = cfg.nodeLogFile;
              scRotation = {
                rpLogLimitBytes = cfg.nodeLogLimitBytes;
                rpKeepFilesNum = cfg.nodeLogKeepFilesNum;
                rpMaxAgeHours = cfg.nodeLogMaxAgeHours;
              };
            }
          ];
        };
      };

      # The blockperf systemd service name cannot contain the string "blockperf"
      # or the bin utility will think it is already running
      systemd.services.blockPerf = {
        after = ["cardano-node.service"];
        wants = ["cardano-node.service"];
        partOf = ["cardano-node.service"];
        wantedBy = ["cardano-node.service"];

        # Ensure service restarts are continuous
        startLimitIntervalSec = 0;

        path = with pkgs; [cfg.package dig gnugrep];

        environment = {
          # Path to the cardano-node blockperf log file
          BLOCKPERF_NODE_LOGFILE = cfg.nodeLogFile;

          # The client identifier; will be given to you with the certificates
          BLOCKPERF_NAME = cfg.blockperfName;

          # Path to the client certificate file
          BLOCKPERF_CLIENT_CERT = sopsPath "blockperf-client-cert.pem";

          # Path to the client key file
          BLOCKPERF_CLIENT_KEY = sopsPath "blockperf-client.key";

          # Path to the Amazon CA file in PEM format, find it here:
          #   https://www.amazontrust.com/repository/AmazonRootCA1.pem
          BLOCKPERF_AMAZON_CA = sopsPath "blockperf-amazon-ca.pem";
        };

        script = ''
          set -euo pipefail

          # Set the node config path
          #
          # The nixos service does not make the config file accessible,
          # so we either need to regenerate it completely, or parse it
          # out of the systemd unit
          START_SCRIPT=$(grep -oP "ExecStart=\K.*" /etc/systemd/system/cardano-node.service)
          NODE_CONFIG=$(grep -oP '   echo "--config \K(.*).json' $(echo "$START_SCRIPT"))
          export BLOCKPERF_NODE_CONFIG="$NODE_CONFIG"

          # Set our public IP using a generic resolver that is cloud/platform independent
          PUBLIC_IP=$(dig +short @resolver1.opendns.com myip.opendns.com)
          export BLOCKPERF_RELAY_PUBLIC_IP="$PUBLIC_IP";

          echo "Blockperf machine Amazon CA: $BLOCKPERF_AMAZON_CA"
          echo "Blockperf machine client cert: $BLOCKPERF_CLIENT_CERT"
          echo "Blockperf machine client key: $BLOCKPERF_CLIENT_KEY"
          echo "Starting blockperf..."
          blockperf run
        '';

        serviceConfig = {
          # Ensure quick restarts on any condition
          Restart = "always";
          RestartSec = 10;
          KillSignal = "SIGINT";
        };
      };

      users.users.cardano-node.extraGroups = ["keys"];

      sops.secrets =
        mkSopsSecret (mkSopsSecretParams "blockperf-client-cert.pem" cfg.blockperfClientCert)
        // mkSopsSecret (mkSopsSecretParams "blockperf-client.key" cfg.blockperfClientKey)
        // mkSopsSecret (mkSopsSecretParams "blockperf-amazon-ca.pem" cfg.blockperfAmazonCA);

      assertions = [
        {
          assertion = cfgNode.instances == 1;
          message = ''The nixos blockperf profile does not currently work with multiple cardano-node instances per machine.'';
        }
      ];
    };
  };
}
