{
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) foldl mdDoc mkOption types recursiveUpdate;
  inherit (types) listOf package submodule;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      ...
    }: let
      pkgGroupSubmodule = submodule {
        options = {
          min = mkOption {
            type = listOf package;
            description = mdDoc "Minimal package group";
            default = with pkgs; [
              b2sum
              xxd
              haskellPackages.cbor-tool
              # TODO:
              # bech32
              # db-analyzer
              # db-synthesizer
              # db-truncater
              # update-cabal-source-repo-checksums
              # ...
            ];
          };

          dev = mkOption {
            type = listOf package;
            description = mdDoc "Developer package group";
            default =
              config.cardano-parts.pkgGroup.min
              ++ [
                # TODO:
                # cabal
                # ghcid
                # ...
              ];
          };

          test = mkOption {
            type = listOf package;
            description = mdDoc "Testing package group";
            default =
              config.cardano-parts.pkgGroup.min
              ++ [
                # TODO:
                # cardano-node
                # cardano-cli
                # cardano-address
                # cardano-wallet
                # ...
              ];
          };

          ops = mkOption {
            type = listOf package;
            description = mdDoc "Operations package group";
            default =
              config.cardano-parts.pkgGroup.test
              ++ [
                # TODO:
                # rain
                # sops
                # terraform
                # wg
                # ...
              ];
          };
        };
      };

      mainSubmodule = submodule {
        options = {
          pkgGroup = mkOption {
            type = pkgGroupSubmodule;
            description = mdDoc "Package groups for downstream consuming devShells";
            default = {};
          };
        };
      };
    in {
      options.cardano-parts = mkOption {
        type = mainSubmodule;
        description = mdDoc "Cardano-parts module options";
        default = {};
      };

      config.devShells = let
        pkgCfg = config.cardano-parts.pkgGroup;
        mkShell = pkgGroup: pkgs.mkShell {packages = pkgCfg.${pkgGroup};};
      in
        foldl (shells: n: recursiveUpdate shells {"cardano-parts-${n}" = mkShell n;}) {} (builtins.attrNames pkgCfg);
    });
  };
}
