flake @ {config, ...}: {
  flake.nixosModules.cardano-group = {lib, ...}: let
    inherit (lib) mkOption types;
    inherit (types) anything attrsOf submodule;
  in {
    options = {
      cardano-group = mkOption {
        default = {};
        type = submodule {
          options = {
            nodeGroup = mkOption {
              type = attrsOf anything;
              inherit (flake.config.flake.cardano-parts.cluster.group) default;
              description = "The cardano group to associate with the nixos node.";
            };
          };
        };
      };
    };
  };
}
