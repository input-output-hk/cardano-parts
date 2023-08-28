flake @ {config, ...}: {
  flake.nixosModules.cardano-parts = {lib, ...}: let
    inherit (lib) mkOption types;
    inherit (types) anything bool attrsOf submodule;

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

        roles = mkOption {
          type = rolesSubmodule;
          description = "Cardano-parts nixos roles submodule";
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

    rolesSubmodule = submodule {
      options = {
        isCardanoCore = mkBoolOpt;
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
  };
}
