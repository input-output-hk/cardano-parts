# nixosModule: config.cardano-parts
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.cardano-parts.cluster.group
#   config.cardano-parts.cluster.perNode.hostAddr
#   config.cardano-parts.cluster.perNode.isCardanoCore
#   config.cardano-parts.cluster.perNode.isCardanoRelay
#   config.cardano-parts.cluster.perNode.isCustom
#   config.cardano-parts.cluster.perNode.isExplorer
#   config.cardano-parts.cluster.perNode.isExplorerBackend
#   config.cardano-parts.cluster.perNode.isFaucet
#   config.cardano-parts.cluster.perNode.isMetadata
#   config.cardano-parts.cluster.perNode.isSnapshots
#   config.cardano-parts.cluster.perNode.nodeId
flake @ {config, ...}: {
  flake.nixosModules.cardano-parts = {lib, ...}: let
    inherit (lib) mkOption types;
    inherit (types) anything attrsOf bool ints nullOr str submodule;

    mkBoolOpt = mkOption {
      type = bool;
      default = false;
    };

    mainSubmodule = submodule {
      options = {
        cluster = mkOption {
          type = clusterSubmodule;
          description = "Cardano-parts nixos cluster submodule";
          default = {};
        };

        perNode = mkOption {
          type = perNodeSubmodule;
          description = "Cardano-parts nixos perNode submodule";
          default = {};
        };
      };
    };

    clusterSubmodule = submodule {
      options = {
        group = mkOption {
          type = attrsOf anything;
          inherit (flake.config.flake.cardano-parts.cluster.group) default;
          description = "The cardano group to associate with the nixos node.";
        };
      };
    };

    perNodeSubmodule = submodule {
      options = {
        hostAddr = mkOption {
          type = str;
          description = "The hostAddr to associate with the nixos node";
          default = "0.0.0.0";
        };

        isCardanoCore = mkBoolOpt;
        isCardanoRelay = mkBoolOpt;
        isSnapshots = mkBoolOpt;
        isCustom = mkBoolOpt;
        isExplorer = mkBoolOpt;
        isExplorerBackend = mkBoolOpt;
        isFaucet = mkBoolOpt;
        isMetadata = mkBoolOpt;

        nodeId = mkOption {
          type = nullOr ints.unsigned;
          description = "The hostAddr to associate with the nixos node";
          default = null;
        };
      };
    };
  in {
    options = {
      # Top level nixos module configuration attr for cardano-parts.
      cardano-parts = mkOption {
        type = mainSubmodule;
      };
    };
  };
}
