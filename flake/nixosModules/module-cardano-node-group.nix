# nixosModule: module-cardano-node-group
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.cardano-node.shareIpv6Address
#   config.cardano-node.totalMaxHeapSizeMbytes
#   config.cardano-node.totalCpuCores
#
# Tips:
#   * This is a cardano-node add-on to the upstream cardano-node nixos service module
#   * This module assists with group deployments
#   * The upstream cardano-node nixos service module should still be imported separately
{moduleWithSystem, ...}: {
  flake.nixosModules.module-cardano-node-group = moduleWithSystem ({config, ...}: nixos @ {
    pkgs,
    lib,
    name,
    nodeResources,
    ...
  }: let
    inherit (builtins) fromJSON readFile;
    inherit (lib) min mkDefault mkIf mkOption types;
    inherit (types) bool float int;
    inherit (nodeResources) cpuCount memMiB;

    inherit (nixos.config.cardano-parts.cluster.group.meta) environmentName;
    inherit (nixos.config.cardano-parts.perNode.lib) cardanoLib;
    inherit (nixos.config.cardano-parts.perNode.meta) cardanoNodePort cardanoNodePrometheusExporterPort hostAddr nodeId;
    inherit (nixos.config.cardano-parts.perNode.pkgs) cardano-node-pkgs;
    inherit (cardanoLib.environments.${environmentName}.nodeConfig) ByronGenesisFile;
    inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;

    cfg = nixos.config.services.cardano-node;
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
      services.cardano-node = {
        totalMaxHeapSizeMbytes = mkOption {
          type = float;
          default = memMiB * 0.790;
        };

        totalCpuCount = mkOption {
          type = int;
          default = min cpuCount (2 * cfg.instances);
        };

        shareIpv6Address = mkOption {
          type = bool;
          default = true;
          description = ''
            Should instances on same machine share ipv6 address.
            Default: true, sets ipv6HostAddr equal to ::1.
            If false use address increments starting from instance index + 1.
          '';
        };
      };
    };

    config = {
      environment.systemPackages = [
        config.cardano-parts.pkgs.bech32
        cardano-node-pkgs.cardano-cli
      ];

      environment.variables = {
        CARDANO_NODE_NETWORK_ID = toString protocolMagic;
        CARDANO_NODE_SOCKET_PATH = cfg.socketPath 0;
        TESTNET_MAGIC = toString protocolMagic;
      };

      # Leave firewall rules to role config
      # networking.firewall = {allowedTCPPorts = [cardanoNodePort];};

      services.cardano-node = {
        inherit hostAddr;

        enable = true;
        environment = environmentName;

        # Setting environments to the perNode cardanoLib default ensures
        # that nodeConfig is obtained from perNode cardanoLib iohk-nix pin.
        environments = mkDefault cardanoLib.environments;

        cardanoNodePackages = mkDefault cardano-node-pkgs;
        nodeId = mkDefault nodeId;

        # Fall back to the iohk-nix environment base topology definition if no custom producers are defined.
        topology = mkDefault (
          if
            (cfg.producers == [])
            && cfg.publicProducers == []
            && cfg.instanceProducers 0 == []
            && cfg.instancePublicProducers 0 == []
          then cardanoLib.mkTopology cardanoLib.environments.${environmentName}
          else null
        );

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

          # TraceMempool makes cpu usage x3
          TraceMempool = false;
        };

        extraServiceConfig = _: {
          serviceConfig = {
            # Allow time to uncompress when restoring db
            TimeoutStartSec = "1h";
            MemoryMax = "${toString (1.15 * cfg.totalMaxHeapSizeMbytes / cfg.instances)}M";
            LimitNOFILE = "65535";
          };
        };

        # https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/runtime_control.html
        rtsArgs = [
          "-N${toString (cfg.totalCpuCount / cfg.instances)}"
          "-A16m"
          "-qg"
          "-qb"
          "-M${toString (cfg.totalMaxHeapSizeMbytes / cfg.instances)}M"
        ];

        systemdSocketActivation = false;
      };

      systemd.services.cardano-node = {
        path = with pkgs; [gnutar gzip];

        preStart = ''
          cd $STATE_DIRECTORY
          if [ -f db-restore.tar.gz ]; then
            rm -rf db-${environmentName}*
            tar xzf db-restore.tar.gz
            rm db-restore.tar.gz
          fi
        '';

        serviceConfig = {
          # Allow time to uncompress when restoring db
          TimeoutStartSec = "1h";
        };
      };

      users.groups.cardano-node = {};
      users.users.cardano-node.group = "cardano-node";
      users.users.cardano-node.isSystemUser = true;

      assertions = [
        {
          assertion = cpuCount >= 2 * cfg.instances;
          message = ''The CPU count on the machine "${name}" will be less 2 per cardano-node instance; performance may be degraded.'';
        }
      ];
    };
  });
}
