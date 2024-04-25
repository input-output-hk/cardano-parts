# nixosModule: role-block-producer
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.mithril-signer.enable
#   config.services.mithril-signer.enableMetrics
#   config.services.mithril-signer.metricsAddress
#   config.services.mithril-signer.metricsPort
#   config.services.mithril-signer.relayEndpoint
#   config.services.mithril-signer.relayPort
#   config.services.mithril-signer.useRelay
#   config.services.mithril-signer.useSignerVerifier
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module to enable a block producer
flake: {
  flake.nixosModules.role-block-producer = {
    config,
    lib,
    name,
    pkgs,
    ...
  }:
    with builtins; let
      inherit (lib) boolToString getExe mkIf mkForce mkOption optionals optionalAttrs types;
      inherit (types) bool port str;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) environmentName;
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (perNodeCfg.pkgs) cardano-cli mithril-signer;
      inherit (cardanoLib.environments.${environmentName}.nodeConfig) ByronGenesisFile Protocol ShelleyGenesisFile;
      inherit (opsLib) mkSopsSecret;
      inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;

      groupCfg = config.cardano-parts.cluster.group;
      mithrilCfg = config.services.mithril-signer;
      nodeCfg = config.services.cardano-node;
      perNodeCfg = config.cardano-parts.perNode;
      groupOutPath = groupFlake.self.outPath;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      pathPrefix = "${groupOutPath}/secrets/groups/${groupName}/deploy/";

      # Byron era secrets path definitions
      signingKey = "${name}-byron-delegate.key";
      delegationCertificate = "${name}-byron-delegation-cert.json";
      byronKeysExist = pathExists (pathPrefix + signingKey) && pathExists (pathPrefix + delegationCertificate);

      # Shelly+ era secrets path definitions
      vrfKey = "${name}-vrf.skey";
      kesKey = "${name}-kes.skey";
      coldVerification = "${name}-cold.vkey";
      operationalCertificate = "${name}.opcert";
      bulkCredentials = "${name}-bulk.creds";

      mkSopsSecretParams = secretName: keyName: {
        inherit groupOutPath groupName name secretName keyName pathPrefix;
        fileOwner = "cardano-node";
        fileGroup = "cardano-node";
        reloadUnits = optionals (nodeCfg.useSystemdReload && nodeCfg.useNewTopology) ["cardano-node.service"];
        restartUnits =
          optionals (!nodeCfg.useSystemdReload || !nodeCfg.useNewTopology) ["cardano-node.service"]
          ++ optionals mithrilCfg.enable ["mithril-signer.service"];
      };

      serviceCfg = rec {
        RealPBFT = {
          signingKey = "/run/secrets/cardano-node-signing";
          delegationCertificate = "/run/secrets/cardano-node-delegation-cert";
        };

        TPraos =
          if perNodeCfg.roles.isCardanoDensePool
          then {
            extraArgs = ["--bulk-credentials-file" "/run/secrets/cardano-node-bulk-credentials"];
          }
          else {
            kesKey = "/run/secrets/cardano-node-kes-signing";
            vrfKey = "/run/secrets/cardano-node-vrf-signing";
            operationalCertificate = "/run/secrets/cardano-node-operational-cert";
          };

        Cardano = TPraos // optionalAttrs byronKeysExist RealPBFT;
      };

      keysCfg = rec {
        RealPBFT =
          (mkSopsSecret (mkSopsSecretParams "cardano-node-signing" signingKey))
          // (mkSopsSecret (mkSopsSecretParams "cardano-node-delegation-cert" delegationCertificate));

        TPraos =
          if perNodeCfg.roles.isCardanoDensePool
          then
            (mkSopsSecret (mkSopsSecretParams "cardano-node-bulk-credentials" bulkCredentials))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-cold-verification" coldVerification))
          else
            (mkSopsSecret (mkSopsSecretParams "cardano-node-vrf-signing" vrfKey))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-kes-signing" kesKey))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-cold-verification" coldVerification))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-operational-cert" operationalCertificate));

        Cardano = TPraos // optionalAttrs byronKeysExist RealPBFT;
      };

      sopsPath = name: config.sops.secrets.${name}.path;
    in {
      options.services.mithril-signer = {
        enable = mkOption {
          type = bool;
          default = nodeCfg.environments.${environmentName} ? mithrilAggregatorEndpointUrl && nodeCfg.environments.${environmentName} ? mithrilSignerConfig;
          description = "Enable this block producer to also run a mithril signer.";
        };

        enableMetrics = mkOption {
          type = bool;
          default = true;
          description = "Enable mithril-signer's built in prometheus metrics server.";
        };

        metricsAddress = mkOption {
          type = str;
          default = "127.0.0.1";
          description = "Set the address to serve mithril-signer's built in prometheus metrics server.";
        };

        metricsPort = mkOption {
          type = port;
          default = 9090;
          description = "Set the port address to serve mithril-signer's built in prometheus metrics server.";
        };

        relayEndpoint = mkOption {
          type = str;
          default = null;
          description = ''
            The relay endpoint the mithril signer must use in a production setup.
            May be either a fully qualified DNS or an IP.
            The port should not be included.
          '';
        };

        relayPort = mkOption {
          type = port;
          default = 3132;
          description = "The relay port the mithril signer must use in a production setup.";
        };

        useRelay = mkOption {
          type = bool;
          default = true;
          description = "Whether to use a proxy relay for requests to avoid leaking the block producer's IP.";
        };

        useSignerVerifier = mkOption {
          type = bool;
          default = true;
          description = "Whether to use a daily run systemd service that will monitor for signed mithril certificates and fail if none are signed by the block producer.";
        };
      };

      config = {
        services.cardano-node =
          serviceCfg.${Protocol}
          // {
            # These are also set from the profile-cardano-node-topology nixos module when role == "bp"
            extraNodeConfig.PeerSharing = false;
            extraNodeConfig.TargetNumberOfRootPeers = 100;
            publicProducers = mkForce [];
            usePeersFromLedgerAfterSlot = -1;
          };

        systemd = {
          services.mithril-signer = mkIf mithrilCfg.enable {
            wantedBy = ["multi-user.target"];

            # Allow up to 10 failures with 30 second restarts in a 15 minute window
            # before entering failure state and alerting
            startLimitBurst = 10;
            startLimitIntervalSec = 900;

            environment = with nodeCfg.environments.${environmentName}.mithrilSignerConfig; {
              AGGREGATOR_ENDPOINT = aggregator_endpoint;
              CARDANO_CLI_PATH = getExe cardano-cli;
              CARDANO_NODE_SOCKET_PATH = nodeCfg.socketPath 0;
              DATA_STORES_DIRECTORY = "/var/lib/mithril-signer/stores";
              DB_DIRECTORY = nodeCfg.databasePath 0;
              ENABLE_METRICS_SERVER = boolToString mithrilCfg.enableMetrics;
              ERA_READER_ADAPTER_PARAMS = era_reader_adapter_params;
              ERA_READER_ADAPTER_TYPE = era_reader_adapter_type;
              KES_SECRET_KEY_PATH = sopsPath "cardano-node-kes-signing";
              METRICS_SERVER_IP = mithrilCfg.metricsAddress;
              METRICS_SERVER_PORT = toString mithrilCfg.metricsPort;
              NETWORK = network;
              OPERATIONAL_CERTIFICATE_PATH = sopsPath "cardano-node-operational-cert";
              RELAY_ENDPOINT = mkIf mithrilCfg.useRelay "${mithrilCfg.relayEndpoint}:${toString mithrilCfg.relayPort}";

              # The mithril signer runtime interval in milliseconds
              RUN_INTERVAL = toString run_interval;

              # Maximum number of records in stores
              STORE_RETENTION_LIMIT = toString store_retention_limit;
            };

            preStart = ''
              set -uo pipefail
              SOCKET="${nodeCfg.socketPath 0}"

              # Wait for the node socket
              while true; do
                [ -S "$SOCKET" ] && sleep 2 && break
                echo "Waiting for cardano node socket at $SOCKET for 2 seconds..."
                sleep 2
              done
            '';

            serviceConfig = {
              ExecStart = getExe (pkgs.writeShellApplication {
                name = "mithril-signer";
                text = ''
                  echo "Starting mithril-signer"
                  ${getExe mithril-signer} -vvv
                '';
              });

              Restart = "always";
              RestartSec = 30;
              User = "cardano-node";
              Group = "cardano-node";

              # Creates /var/lib/mithril-signer
              StateDirectory = "mithril-signer";

              # Wait up to an hour for the node socket to appear on preStart.
              # Allow long ledger replays and/or db-restore gunzip, including on slow systems
              TimeoutStartSec = 24 * 3600;
            };
          };

          services.mithril-signer-verifier = mkIf (mithrilCfg.enable
            && mithrilCfg.useSignerVerifier) {
            wantedBy = ["multi-user.target"];

            environment = with nodeCfg.environments.${environmentName}.mithrilSignerConfig; {
              AGGREGATOR_ENDPOINT = aggregator_endpoint;
              CARDANO_NODE_SOCKET_PATH = nodeCfg.socketPath 0;
              CARDANO_NODE_NETWORK_ID = toString protocolMagic;
              RELAY_ENDPOINT = mkIf mithrilCfg.useRelay "${mithrilCfg.relayEndpoint}:${toString mithrilCfg.relayPort}";
            };

            preStart = ''
              while ! [ -s /run/secrets/cardano-node-cold-verification ]; do
                echo "Waiting 10 seconds for secret /run/secrets/cardano-node-cold-verification to become available..."
                sleep 10
              done
            '';

            serviceConfig = {
              Type = "oneshot";

              ExecStart = getExe (pkgs.writeShellApplication {
                name = "mithril-signer-verifier";
                runtimeInputs = with pkgs; [cardano-cli curl gnugrep jq];
                text = ''
                  echo "Starting mithril-signer-verifier"
                  POOL_ID=$(cardano-cli stake-pool id \
                    --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
                    --output-format bech32)

                  CURL_WITH_RELAY() {
                    curl -s ${
                    if mithrilCfg.useRelay
                    then "-x \"$RELAY_ENDPOINT\""
                    else ""
                  } "$1"
                  }

                  CERTIFICATES_RESPONSE=$(CURL_WITH_RELAY "$AGGREGATOR_ENDPOINT/certificates")
                  CERTIFICATES_COUNT=$(jq '. | length' <<< "$CERTIFICATES_RESPONSE")

                  echo "For pool id $POOL_ID:"
                  SIGNED=0
                  while read -r HASH; do
                      RESPONSE=$(CURL_WITH_RELAY "$AGGREGATOR_ENDPOINT/certificate/$HASH")
                      if jq -r '.metadata.signers[].party_id' <<< "$RESPONSE" | grep -qe "$POOL_ID"; then
                        echo "Certificate sealed at $(jq -r '.metadata.sealed_at' <<< "$RESPONSE") with hash $HASH has been signed"
                        SIGNED=$((SIGNED+1))
                      fi
                  done < <(jq -r '.[] | .hash' <<< "$CERTIFICATES_RESPONSE")

                  echo "Of the $CERTIFICATES_COUNT most recent certificates, $SIGNED have been signed by this pool"

                  if [ "$SIGNED" -eq "0" ]; then
                    exit 1
                  else
                    exit 0
                  fi
                '';
              });

              User = "cardano-node";
              Group = "cardano-node";
            };
          };

          timers.mithril-signer-verifier = mkIf (mithrilCfg.enable
            && mithrilCfg.useSignerVerifier) {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = "daily";
              Unit = "mithril-signer-verifier.service";
            };
          };
        };

        sops.secrets = keysCfg.${Protocol};
        users.users.cardano-node.extraGroups = ["keys"];

        environment.shellAliases = {
          cardano-show-kes-period-info = ''
            cardano-cli \
              query kes-period-info \
              --op-cert-file /run/secrets/cardano-node-operational-cert
          '';

          cardano-show-leadership-schedule = ''
            cardano-cli \
              query leadership-schedule \
              --genesis ${ShelleyGenesisFile} \
              --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
              --vrf-signing-key-file /run/secrets/cardano-node-vrf-signing \
              --current
          '';

          cardano-show-pool-hash = ''
            cardano-cli \
              stake-pool id \
              --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
              --output-format hex
          '';

          cardano-show-pool-id = ''
            cardano-cli \
              stake-pool id \
              --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
              --output-format bech32
          '';

          cardano-show-pool-stake-snapshot = ''
            cardano-cli \
              query stake-snapshot \
              --stake-pool-id "$(cardano-show-pool-id)"
          '';
        };

        assertions = [
          {
            assertion = nodeCfg.instances == 1;
            message = ''The role block producer does not currently work with multiple cardano-node instances per machine.'';
          }
        ];
      };
    };
}
