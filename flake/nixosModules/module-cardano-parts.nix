# nixosModule: module-cardano-parts
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.cardano-parts.cluster.group.<...>                             # Inherited from flakeModule cluster.group assignment
#   config.cardano-parts.perNode.lib.cardanoLib
#   config.cardano-parts.perNode.lib.opsLib
#   config.cardano-parts.perNode.lib.topologyLib
#   config.cardano-parts.perNode.meta.cardanoDbSyncPrometheusExporterPort
#   config.cardano-parts.perNode.meta.cardanoNodePort
#   config.cardano-parts.perNode.meta.cardanoNodePrometheusExporterPort
#   config.cardano-parts.perNode.meta.cardanoSmashDelistedPools
#   config.cardano-parts.perNode.meta.cardano-db-sync-service
#   config.cardano-parts.perNode.meta.cardano-faucet-service
#   config.cardano-parts.perNode.meta.cardano-metadata-service
#   config.cardano-parts.perNode.meta.cardano-node-service
#   config.cardano-parts.perNode.meta.cardano-smash-service
#   config.cardano-parts.perNode.meta.enableAlertCount
#   config.cardano-parts.perNode.meta.hostAddr
#   config.cardano-parts.perNode.meta.nodeId
#   config.cardano-parts.perNode.pkgs.blockperf
#   config.cardano-parts.perNode.pkgs.cardano-cli
#   config.cardano-parts.perNode.pkgs.cardano-db-sync
#   config.cardano-parts.perNode.pkgs.cardano-db-sync-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-db-tool
#   config.cardano-parts.perNode.pkgs.cardano-faucet
#   config.cardano-parts.perNode.pkgs.cardano-metadata-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-node
#   config.cardano-parts.perNode.pkgs.cardano-node-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-smash
#   config.cardano-parts.perNode.pkgs.cardano-submit-api
#   config.cardano-parts.perNode.pkgs.mithril-client-cli
#   config.cardano-parts.perNode.pkgs.mithril-signer
#   config.cardano-parts.perNode.roles.isCardanoDensePool
flake @ {moduleWithSystem, ...}: {
  flake.nixosModules.module-cardano-parts = moduleWithSystem ({system}: {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) foldl' mdDoc mkOption recursiveUpdate types;
    inherit (types) anything attrsOf bool ints listOf package port nullOr str submodule;

    cfg = config.cardano-parts.cluster;

    mkBoolOpt = mkOption {
      type = bool;
      default = false;
    };

    mkPkgOpt = name: pkg: {
      ${name} = mkOption {
        type = package;
        description = mdDoc "The cardano-parts nixos default package for ${name}.";
        default = pkg;
      };
    };

    mkSpecialOpt = name: type: specialPkg: {
      ${name} = mkOption {
        inherit type;
        description = mdDoc "The cardano-parts nixos default special package for ${name}.";
        default = specialPkg;
      };
    };

    mainSubmodule = submodule {
      options = {
        cluster = mkOption {
          type = clusterSubmodule;
          description = mdDoc "Cardano-parts nixos cluster submodule";
          default = {};
        };

        perNode = mkOption {
          type = perNodeSubmodule;
          description = mdDoc "Cardano-parts nixos perNode submodule";
          default = {};
        };
      };
    };

    clusterSubmodule = submodule {
      options = {
        group = mkOption {
          type = attrsOf anything;
          inherit (flake.config.flake.cardano-parts.cluster.groups) default;
          description = mdDoc "The cardano group to associate with the nixos node.";
        };
      };
    };

    perNodeSubmodule = submodule {
      options = {
        lib = mkOption {
          type = libSubmodule;
          description = mdDoc "Cardano-parts nixos perNode lib submodule";
          default = {};
        };

        meta = mkOption {
          type = metaSubmodule;
          description = mdDoc "Cardano-parts nixos perNode meta submodule";
          default = {};
        };

        pkgs = mkOption {
          type = pkgsSubmodule;
          description = mdDoc "Cardano-parts nixos perNode pkgs submodule";
          default = {};
        };

        roles = mkOption {
          type = rolesSubmodule;
          description = mdDoc "Cardano-parts nixos perNode roles submodule";
          default = {};
        };
      };
    };

    libSubmodule = submodule {
      options = foldl' recursiveUpdate {} [
        (mkSpecialOpt "cardanoLib" (attrsOf anything) (cfg.group.lib.cardanoLib system))
        (mkSpecialOpt "opsLib" (attrsOf anything) (cfg.group.lib.opsLib pkgs))
        (mkSpecialOpt "topologyLib" (attrsOf anything) (cfg.group.lib.topologyLib cfg.group))
      ];
    };

    metaSubmodule = submodule {
      options = {
        cardanoDbSyncPrometheusExporterPort = mkOption {
          type = port;
          description = mdDoc "The port to associate with the nixos cardano-db-sync prometheus exporter.";
          default = cfg.group.meta.cardanoDbSyncPrometheusExporterPort;
        };

        cardanoNodePort = mkOption {
          type = port;
          description = mdDoc "The port to associate with the nixos cardano-node.";
          default = cfg.group.meta.cardanoNodePort;
        };

        cardanoNodePrometheusExporterPort = mkOption {
          type = port;
          description = mdDoc "The port to associate with the nixos cardano-node prometheus exporter.";
          default = cfg.group.meta.cardanoNodePrometheusExporterPort;
        };

        cardanoSmashDelistedPools = mkOption {
          type = listOf str;
          description = mdDoc "The cardano-smash delisted pools.";
          default = cfg.group.meta.cardanoSmashDelistedPools;
        };

        cardano-db-sync-service = mkOption {
          type = str;
          description = mdDoc "The cardano-db-sync-service import path string.";
          default = cfg.group.meta.cardano-db-sync-service;
        };

        cardano-faucet-service = mkOption {
          type = str;
          description = mdDoc "The cardano-faucet-service import path string.";
          default = cfg.group.meta.cardano-faucet-service;
        };

        cardano-metadata-service = mkOption {
          type = str;
          description = mdDoc "The cardano-metadata-service import path string.";
          default = cfg.group.meta.cardano-metadata-service;
        };

        cardano-node-service = mkOption {
          type = str;
          description = mdDoc "The cardano-node-service import path string.";
          default = cfg.group.meta.cardano-node-service;
        };

        cardano-smash-service = mkOption {
          type = str;
          description = mdDoc "The cardano-smash-service import path string.";
          default = cfg.group.meta.cardano-smash-service;
        };

        enableAlertCount = mkOption {
          type = bool;
          description = mdDoc ''
            Whether to count this machine as an expected machine to appear in grafana/prometheus metrics.

            In cases where this machine may be created, but mostly kept in a stopped state such that it will
            not push metrics to the monitoring server, this option can be disabled to exclude it from the
            expected machine count.

            The value of this boolean will affect the alert rules applied by running `just tofu grafana apply`
            from a cardano-parts ops devShell.
          '';
          default = true;
        };

        hostAddr = mkOption {
          type = str;
          description = mdDoc "The hostAddr to associate with the nixos cardano-node";
          default = "0.0.0.0";
        };

        nodeId = mkOption {
          type = nullOr ints.unsigned;
          description = mdDoc "The hostAddr to associate with the nixos cardano-node";
          default = 0;
        };
      };
    };

    pkgsSubmodule = submodule {
      options = foldl' recursiveUpdate {} [
        (mkPkgOpt "blockperf" (cfg.group.pkgs.blockperf system))
        (mkPkgOpt "cardano-cli" (cfg.group.pkgs.cardano-cli system))
        (mkPkgOpt "cardano-db-sync" (cfg.group.pkgs.cardano-db-sync system))
        (mkPkgOpt "cardano-db-tool" (cfg.group.pkgs.cardano-db-tool system))
        (mkPkgOpt "cardano-faucet" (cfg.group.pkgs.cardano-faucet system))
        (mkPkgOpt "cardano-node" (cfg.group.pkgs.cardano-node system))
        (mkPkgOpt "cardano-smash" (cfg.group.pkgs.cardano-smash system))
        (mkPkgOpt "cardano-submit-api" (cfg.group.pkgs.cardano-submit-api system))
        (mkPkgOpt "mithril-client-cli" (cfg.group.pkgs.mithril-client-cli system))
        (mkPkgOpt "mithril-signer" (cfg.group.pkgs.mithril-signer system))
        (mkSpecialOpt "cardano-db-sync-pkgs" lib.types.attrs (cfg.group.pkgs.cardano-db-sync-pkgs system))
        (mkSpecialOpt "cardano-metadata-pkgs" lib.types.attrs (cfg.group.pkgs.cardano-metadata-pkgs system))
        (mkSpecialOpt "cardano-node-pkgs" (attrsOf anything) (cfg.group.pkgs.cardano-node-pkgs system))
      ];
    };

    rolesSubmodule = submodule {
      options = {
        isCardanoDensePool = mkBoolOpt;
      };
    };
  in {
    options = {
      # Top level nixos module configuration attr for cardano-parts.
      cardano-parts = mkOption {
        type = mainSubmodule;
      };
    };
  });
}
