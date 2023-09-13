# nixosModule: config.cardano-parts
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.cardano-parts.cluster.group.<...>                             # Inherited from flakeModule cluster.group assignment
#   config.cardano-parts.perNode.lib.cardanoLib
#   config.cardano-parts.perNode.lib.topologyLib
#   config.cardano-parts.perNode.meta.cardanoNodePort
#   config.cardano-parts.perNode.meta.cardanoNodePrometheusExporterPort
#   config.cardano-parts.perNode.meta.cardano-node-service
#   config.cardano-parts.perNode.meta.hostAddr
#   config.cardano-parts.perNode.meta.nodeId
#   config.cardano-parts.perNode.pkgs.cardano-cli
#   config.cardano-parts.perNode.pkgs.cardano-node
#   config.cardano-parts.perNode.pkgs.cardano-node-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-submit-api
#   config.cardano-parts.perNode.roles.isCardanoCore
#   config.cardano-parts.perNode.roles.isCardanoDensePool
#   config.cardano-parts.perNode.roles.isCardanoRelay
#   config.cardano-parts.perNode.roles.isCustom
#   config.cardano-parts.perNode.roles.isExplorer
#   config.cardano-parts.perNode.roles.isExplorerBackend
#   config.cardano-parts.perNode.roles.isFaucet
#   config.cardano-parts.perNode.roles.isMetadata
#   config.cardano-parts.perNode.roles.isSnapshots
flake @ {moduleWithSystem, ...}: {
  flake.nixosModules.cardano-parts = moduleWithSystem ({system}: {
    config,
    lib,
    ...
  }: let
    inherit (lib) foldl' mdDoc mkOption recursiveUpdate types;
    inherit (types) anything attrsOf bool ints package port nullOr str submodule;

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
          inherit (flake.config.flake.cardano-parts.cluster.group) default;
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
        (mkSpecialOpt "topologyLib" (attrsOf anything) (cfg.group.lib.topologyLib cfg.group))
      ];
    };

    metaSubmodule = submodule {
      options = {
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

        cardano-node-service = mkOption {
          type = str;
          description = mdDoc "The cardano-node-service import path string.";
          default = cfg.group.meta.cardano-node-service;
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
        (mkPkgOpt "cardano-cli" (cfg.group.pkgs.cardano-cli system))
        (mkPkgOpt "cardano-node" (cfg.group.pkgs.cardano-node system))
        (mkPkgOpt "cardano-submit-api" (cfg.group.pkgs.cardano-submit-api system))
        (mkSpecialOpt "cardano-node-pkgs" (attrsOf anything) (cfg.group.pkgs.cardano-node-pkgs system))
      ];
    };

    rolesSubmodule = submodule {
      options = {
        isCardanoCore = mkBoolOpt;
        isCardanoDensePool = mkBoolOpt;
        isCardanoRelay = mkBoolOpt;
        isSnapshots = mkBoolOpt;
        isCustom = mkBoolOpt;
        isExplorer = mkBoolOpt;
        isExplorerBackend = mkBoolOpt;
        isFaucet = mkBoolOpt;
        isMetadata = mkBoolOpt;
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
