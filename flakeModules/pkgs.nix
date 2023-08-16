{
  localFlake,
  withSystem,
}: flake @ {
  self,
  flake-parts-lib,
  lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) foldl mdDoc mkDefault mkOption optionalAttrs optionalString recursiveUpdate types;
  inherit (types) anything attrs attrsOf bool enum nullOr listOf package str submodule;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      system,
      ...
    }: let
      cfg = config.cardano-parts;
      cfgPkgs = cfg.pkgs;
      flakeCfg = flake.config.flake.cardano-parts;

      withLocal = withSystem system;

      mainSubmodule = submodule {
        options = {
          pkgs = mkOption {
            type = pkgsSubmodule;
            description = mdDoc "Cardano-parts packages options";
            default = {};
          };
        };
      };

      pkgsSubmodule = submodule {
        options = {
        };
      };
    in {
      _file = ./pkgs.nix;

      # perSystem level option definition
      options.cardano-parts = mkOption {
        type = mainSubmodule;
      };

      config = {
        cardano-parts = mkDefault {};
      };
    });
  };
}
