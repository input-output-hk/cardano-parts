# nixosModule: profile-cardano-node-group
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-node.shareIpv6Address
#   config.services.cardano-node.totalCpuCores
#   config.services.cardano-node.totalMaxHeapSizeMiB
#   config.services.mithril-client.enable
#   config.services.mithril-client.aggregatorEndpointUrl
#   config.services.mithril-client.genesisVerificationKey
#   config.services.mithril-client.snapshotDigest
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module
#   * This module assists with group deployments
#   * The upstream cardano-node nixos service module should still be imported separately
{moduleWithSystem, ...}: {
  flake.nixosModules.profile-cardano-node-group = moduleWithSystem ({
    config,
    self',
    ...
  }: nixos @ {
    pkgs,
    lib,
    name,
    nodeResources,
    ...
  }: let
    inherit (builtins) elem fromJSON readFile;
    inherit (lib) flatten foldl' getExe min mkDefault mkIf mkOption optionalString range recursiveUpdate types;
    inherit (types) bool float ints oneOf str;
    inherit (nodeResources) cpuCount memMiB;

    inherit (nixos.config.cardano-parts.cluster.group.meta) environmentName;
    inherit (nixos.config.cardano-parts.perNode.lib) cardanoLib;
    inherit (nixos.config.cardano-parts.perNode.meta) cardanoNodePort cardanoNodePrometheusExporterPort hostAddr nodeId;
    inherit (nixos.config.cardano-parts.perNode.pkgs) cardano-node cardano-node-pkgs mithril-client-cli;
    inherit (cardanoLib) mkEdgeTopology mkEdgeTopologyP2P;
    inherit (cardanoLib.environments.${environmentName}.nodeConfig) ByronGenesisFile ShelleyGenesisFile;
    inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;
    inherit (fromJSON (readFile ShelleyGenesisFile)) slotsPerKESPeriod;

    mkTopology = env: let
      legacyTopology = mkEdgeTopology {
        edgeNodes = [env.relaysNew];
        valency = 2;
        edgePort = env.edgePort or 3001;
      };

      p2pTopology = mkEdgeTopologyP2P {
        inherit (env) edgeNodes;
        useLedgerAfterSlot = env.usePeersFromLedgerAfterSlot;
      };
    in
      if cfg.useNewTopology
      then p2pTopology
      else legacyTopology;

    iRange = range 0 (cfg.instances - 1);

    cfg = nixos.config.services.cardano-node;
    cfgMithril = nixos.config.services.mithril-client;
  in {
    # Leave the import of the upstream cardano-node service for
    # cardano-parts consuming repos so that service import can be customized.
    #
    # Unfortunately, we can't customize the import based on
    # perNode nixos options as this leads to infinite recursion.
    #
    # imports = [
    #   nixos.config.cardano-parts.perNode.pkgs.cardano-node-service;
    # ];

    options = {
      services = {
        cardano-node = {
          shareIpv6Address = mkOption {
            type = bool;
            default = true;
            description = ''
              Should instances on same machine share ipv6 address.
              Default: true, sets ipv6HostAddr equal to ::1.
              If false use address increments starting from instance index + 1.
            '';
          };

          shareNodeSocket = mkOption {
            type = bool;
            default = false;
            description = ''
              Makes the node socket for instance 0 only group writeable.
              This is done using an inotifywait service to avoid long systemd job startups using postStart.
            '';
          };

          totalCpuCount = mkOption {
            type = ints.positive;
            default = min cpuCount (2 * cfg.instances);
          };

          totalMaxHeapSizeMiB = mkOption {
            type = oneOf [ints.positive float];
            default = memMiB * 0.790;
          };
        };

        mithril-client = {
          enable = mkOption {
            type = bool;
            default = cfg.environments.${environmentName} ? mithrilAggregatorEndpointUrl && elem environmentName ["preprod" "preview"];
            description = "Allow mithril-client to bootstrap cardano-node chain state.";
          };

          aggregatorEndpointUrl = mkOption {
            type = str;
            default = cfg.environments.${environmentName}.mithrilAggregatorEndpointUrl or "";
            description = "The mithril aggregator endpoint url.";
          };

          genesisVerificationKey = mkOption {
            type = str;
            default = cfg.environments.${environmentName}.mithrilGenesisVerificationKey or "";
            description = "The mithril genesis verification key.";
          };

          snapshotDigest = mkOption {
            type = str;
            default = "latest";
            description = "The mithril snapshot digest id or `latest` for the most recently taken snapshot.";
          };
        };
      };
    };

    config = {
      environment.systemPackages = [
        config.cardano-parts.pkgs.bech32
        cardano-node-pkgs.cardano-cli
        config.cardano-parts.pkgs.db-analyser
        config.cardano-parts.pkgs.db-synthesizer
        config.cardano-parts.pkgs.db-truncater
        self'.packages.db-analyser-ng
        self'.packages.db-synthesizer-ng
        self'.packages.db-truncater-ng
        mithril-client-cli
      ];

      environment = {
        shellAliases = {
          cardano-reload-topology = ''
            pkill --echo --signal SIGHUP cardano-node \
              | sed 's/killed/signaled to reload p2p topology, check logs for "Performing topology configuration update"/g'
          '';

          cardano-show-kes-period = ''
            echo "Current KES period for environment ${environmentName}: $(($(cardano-cli query tip | jq .slot) / ${toString slotsPerKESPeriod}))"
          '';

          cardano-show-p2p-conns = ''
            pkill --echo --signal SIGUSR1 cardano-node \
              | sed 's/killed/signaled to dump p2p TrState info, check logs for details/g'
          '';
        };

        variables = {
          CARDANO_NODE_NETWORK_ID = toString protocolMagic;
          CARDANO_NODE_SNAPSHOT_URL = mkIf (environmentName == "mainnet") "https://update-cardano-mainnet.iohk.io/cardano-node-state/db-mainnet.tar.gz";
          CARDANO_NODE_SNAPSHOT_SHA256_URL = mkIf (environmentName == "mainnet") "https://update-cardano-mainnet.iohk.io/cardano-node-state/db-mainnet.tar.gz.sha256sum";
          CARDANO_NODE_SOCKET_PATH = cfg.socketPath 0;
          AGGREGATOR_ENDPOINT = mkIf cfgMithril.enable cfgMithril.aggregatorEndpointUrl;
          GENESIS_VERIFICATION_KEY = mkIf cfgMithril.enable cfgMithril.genesisVerificationKey;
          TESTNET_MAGIC = toString protocolMagic;
        };
      };

      # Leave firewall rules to role config
      # networking.firewall = {allowedTCPPorts = [cardanoNodePort];};

      services.cardano-node = {
        enable = true;
        environment = environmentName;

        # Setting environments to the perNode cardanoLib default ensures
        # that nodeConfig is obtained from perNode cardanoLib iohk-nix pin.
        environments = mkDefault cardanoLib.environments;

        package = mkDefault cardano-node;
        cardanoNodePackages = mkDefault cardano-node-pkgs;
        nodeId = mkDefault nodeId;

        # Fall back to the iohk-nix environment base topology definition if no custom producers are defined.
        useNewTopology = mkDefault true;
        useSystemdReload = mkDefault true;
        topology = mkDefault (
          if
            (cfg.producers == [])
            && cfg.publicProducers == []
            && (flatten (map cfg.instanceProducers iRange)) == []
            && (flatten (map cfg.instancePublicProducers iRange)) == []
          then mkTopology cardanoLib.environments.${environmentName}
          else null
        );

        hostAddr = mkDefault hostAddr;
        ipv6HostAddr = mkIf (cfg.instances > 1) (
          if cfg.shareIpv6Address
          then "::1"
          else (i: "::127.0.0.${toString (i + 1)}")
        );

        port = mkDefault cardanoNodePort;
        producers = mkDefault [];
        publicProducers = mkDefault [];

        extraNodeConfig = {
          hasPrometheus = [cfg.hostAddr cardanoNodePrometheusExporterPort];

          # The maximum number of used peers when fetching newly forged blocks
          MaxConcurrencyDeadline = 4;

          # Use Journald output
          setupScribes = [
            {
              scKind = "JournalSK";
              scName = "cardano";
              scFormat = "ScText";
            }
          ];

          defaultScribes = [["JournalSK" "cardano"]];
        };

        extraServiceConfig = _: {
          # Allow up to 10 failures with 30 second restarts in a 15 minute window
          # before entering failure state and alerting
          startLimitBurst = 10;
          startLimitIntervalSec = 900;

          serviceConfig = {
            MemoryMax = "${toString (1.15 * cfg.totalMaxHeapSizeMiB / cfg.instances)}M";
            LimitNOFILE = "65535";

            # Ensure quick restarts on any condition
            Restart = "always";
            RestartSec = 30;
          };
        };

        # https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/runtime_control.html
        rtsArgs = [
          "-N${toString (cfg.totalCpuCount / cfg.instances)}"
          "-A16m"
          "-qg"
          "-qb"
          "-M${toString (cfg.totalMaxHeapSizeMiB / cfg.instances)}M"
        ];

        systemdSocketActivation = false;
      };

      systemd.services = let
        serviceName = i:
          if cfg.instances == 1
          then "cardano-node"
          else "cardano-node-${toString i}";
      in
        {
          cardano-node-socket-share = mkIf cfg.shareNodeSocket {
            after = ["cardano-node.service"];
            wants = ["cardano-node.service"];
            partOf = ["cardano-node.service"];
            wantedBy = ["cardano-node.service"];

            # Allow up to 10 failures with 30 second restarts in a 15 minute window
            # before entering failure state and alerting
            startLimitBurst = 10;
            startLimitIntervalSec = 900;

            serviceConfig = {
              ExecStart = getExe (pkgs.writeShellApplication {
                name = "cardano-node-socket-share";
                runtimeInputs = with pkgs; [inotify-tools];
                text = ''
                  TARGET="${cfg.socketPath 0}"
                  NAME=$(basename "$TARGET")
                  DIR=$(dirname "$TARGET")

                  MK_SOCKET_WRITABLE() {
                    if [ -S "$TARGET" ]; then
                      chmod g+w "$TARGET"
                      echo "Cardano-node socket file for instance 0 at $TARGET has been made group writeable"
                    fi
                  }

                  # For the case the socket already exists when this service starts
                  MK_SOCKET_WRITABLE

                  while inotifywait --include "$NAME" "$DIR"; do
                    MK_SOCKET_WRITABLE
                  done
                '';
              });

              Restart = "always";
              RestartSec = 30;
            };
          };
        }
        // foldl' (acc: i:
          recursiveUpdate acc {
            "${serviceName i}" = {
              serviceConfig = {
                ExecStartPre = getExe (pkgs.writeShellApplication {
                  name = "cardano-node-pre-start";
                  runtimeInputs = with pkgs; [gnutar gzip];
                  text = let
                    mithril-client-bootstrap = optionalString cfgMithril.enable ''
                      TMPSTATE="''${DB_DIR}-mithril"
                      rm -rf "$TMPSTATE"
                      if ! [ -d "$DB_DIR" ]; then
                        echo "Bootstrapping cardano-node-${toString i} state from mithril"
                        ${getExe mithril-client-cli} \
                          -vvv \
                          --aggregator-endpoint "${cfgMithril.aggregatorEndpointUrl}" \
                          snapshot \
                          download \
                          "${cfgMithril.snapshotDigest}" \
                          --download-dir "$TMPSTATE" \
                          --genesis-verification-key "${cfgMithril.genesisVerificationKey}"
                        mv "$TMPSTATE/db" "$DB_DIR"
                        rm -rf "$TMPSTATE"
                        echo "Mithril bootstrap complete for $DB_DIR"
                      fi
                    '';
                  in ''
                    INSTANCE="${toString i}"
                    DB_DIR="${
                      if i == 0
                      then "db-${environmentName}"
                      else "db-${environmentName}-${toString i}"
                    }"
                    cd "$STATE_DIRECTORY"

                    # Legacy: if a db-restore.tar.gz file exists, use it to replace state of the first node instance
                    if [ -f db-restore.tar.gz ] && [ "$INSTANCE" == "0" ]; then
                      echo "Restoring database from db-restore.tar.gz to $DB_DIR"
                      rm -rf "$DB_DIR"
                      tar xzf db-restore.tar.gz
                      rm db-restore.tar.gz
                    fi

                    # Mithril-client bootstrap code will follow if nixos option service.mithril-client.enable is true
                    ${mithril-client-bootstrap}
                  '';
                });

                # Allow long ledger replays and/or db-restore gunzip, including on slow systems
                TimeoutStartSec = "infinity";
              };
            };
          }) {}
        iRange;

      users = {
        groups.cardano-node = {};
        users.cardano-node = {
          group = "cardano-node";
          isSystemUser = true;
        };
      };

      assertions = [
        {
          assertion = cpuCount >= 2 * cfg.instances;
          message = ''The CPU count on the machine "${name}" will be less 2 per cardano-node instance; performance may be degraded.'';
        }
      ];
    };
  });
}
