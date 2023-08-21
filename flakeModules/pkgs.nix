# flakeModule: inputs.cardano-parts.flakeModules.pkgs
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.pkgs.cardano-lib
#   perSystem.cardano-parts.pkgs.bech32
#   perSystem.cardano-parts.pkgs.cardano-address
#   perSystem.cardano-parts.pkgs.cardano-cli
#   perSystem.cardano-parts.pkgs.cardano-cli-ng
#   perSystem.cardano-parts.pkgs.cardano-db-sync
#   perSystem.cardano-parts.pkgs.cardano-db-tool
#   perSystem.cardano-parts.pkgs.cardano-faucet
#   perSystem.cardano-parts.pkgs.cardano-node
#   perSystem.cardano-parts.pkgs.cardano-node-ng
#   perSystem.cardano-parts.pkgs.cardano-submit-api
#   perSystem.cardano-parts.pkgs.cardano-tracer
#   perSystem.cardano-parts.pkgs.cardano-wallet
#   perSystem.cardano-parts.pkgs.db-analyser
#   perSystem.cardano-parts.pkgs.db-synthesizer
#   perSystem.cardano-parts.pkgs.db-truncater
#   perSystem.cardano-parts.pkgs.metadata-server
#   perSystem.cardano-parts.pkgs.metadata-sync
#   perSystem.cardano-parts.pkgs.metadata-validator-github
#   perSystem.cardano-parts.pkgs.metadata-webhook
#   perSystem.cardano-parts.pkgs.token-metadata-creator
#
# Tips:
#   * perSystem attrs are simply accessed through [config.]<...> from within system module context
#   * flake level attrs are accessed from flake at [config.]flake.cardano-parts.pkgs.<...>
{localFlake}: flake @ {
  flake-parts-lib,
  lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mdDoc mkOption;
  inherit (lib.types) anything package submodule;

  mainSubmodule = submodule {
    options = {
      pkgs = mkOption {
        type = mainPkgsSubmodule;
        description = mdDoc "Cardano-parts packages options";
        default = {};
      };
    };
  };

  mainPkgsSubmodule = submodule {
    options = {
      cardanoLib = mkOption {
        type = anything;
        description = mdDoc ''
          The cardano-parts system dependent default package for cardanoLib.

          Iohk-nix cardanoLib is not a proper package derivation and
          fails flake .#packages.$system type checking. On the other hand,
          in .#legacyPackages.$system it is ignored but useable.

          Since cardanoLib is system dependent, placing it in
          legacyPackages seems most appropriate.

          The default definition must be a function of system.
        '';
        default = system:
          (import localFlake.inputs.nixpkgs {
            inherit system;
            overlays = map (
              overlay: localFlake.inputs.iohk-nix.overlays.${overlay}
            ) (builtins.attrNames localFlake.inputs.iohk-nix.overlays);
          })
          .cardanoLib;
      };
    };
  };
in
  with lib; {
    options = {
      # Top level option definition
      flake.cardano-parts = mkOption {
        type = mainSubmodule;
      };

      perSystem = mkPerSystemOption ({
        config,
        pkgs,
        system,
        ...
      }: let
        cfg = config.cardano-parts;
        cfgPkgs = cfg.pkgs;

        mkPkg = name: pkg: {
          ${name} = mkOption {
            type = package;
            description = mdDoc "The cardano-parts default package for ${name}.";
            default = pkg;
          };
        };

        mkWrapper = name: pkg:
          (pkgs.writeShellScriptBin name ''
            exec ${getExe pkg} "$@"
          '')
          .overrideAttrs (_: {
            meta.description = "Wrapper for ${getName pkg}${
              if getVersion pkg != ""
              then " (${getVersion pkg})"
              else ""
            }";
          });

        mainPerSystemSubmodule = submodule {
          options = {
            pkgs = mkOption {
              type = pkgsSubmodule;
              description = mdDoc "Cardano-parts packages options";
              default = {};
            };
          };
        };

        pkgsSubmodule = submodule {
          options = foldl' recursiveUpdate {} [
            (mkPkg "bech32" localFlake.inputs.cardano-node.packages.${system}.bech32)
            (mkPkg "cardano-address" localFlake.inputs.cardano-wallet.packages.${system}.cardano-address)
            (mkPkg "cardano-cli" localFlake.inputs.cardano-node.packages.${system}.cardano-cli)
            (mkPkg "cardano-cli-ng" (mkWrapper "cardano-cli-ng" localFlake.inputs.cardano-cli-ng.packages.${system}."cardano-cli:exe:cardano-cli"))
            (mkPkg "cardano-db-sync" localFlake.inputs.cardano-db-sync.packages.${system}.cardano-db-sync)
            (mkPkg "cardano-db-tool" localFlake.inputs.cardano-db-sync.packages.${system}.cardano-db-tool)
            (mkPkg "cardano-faucet" localFlake.inputs.cardano-faucet.packages.${system}."cardano-faucet:exe:cardano-faucet")
            (mkPkg "cardano-node" localFlake.inputs.cardano-node.packages.${system}.cardano-node)
            (mkPkg "cardano-node-ng" (mkWrapper "cardano-node-ng" localFlake.inputs.cardano-node-ng.packages.${system}.cardano-node))
            (mkPkg "cardano-submit-api" localFlake.inputs.cardano-node.packages.${system}.cardano-submit-api)
            (mkPkg "cardano-tracer" localFlake.inputs.cardano-node.packages.${system}.cardano-tracer)
            (mkPkg "cardano-wallet" localFlake.inputs.cardano-wallet.packages.${system}.cardano-wallet)
            (mkPkg "db-analyser" localFlake.inputs.cardano-node.packages.${system}.db-analyser)
            (mkPkg "db-synthesizer" localFlake.inputs.cardano-node.packages.${system}.db-synthesizer)
            (mkPkg "db-truncater" localFlake.inputs.cardano-node-ng.packages.${system}.db-truncater)
            (mkPkg "metadata-server" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-server)
            (mkPkg "metadata-sync" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-sync)
            (mkPkg "metadata-validator-github" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-validator-github)
            (mkPkg "metadata-webhook" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-webhook)
            (mkPkg "token-metadata-creator" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.token-metadata-creator)
          ];
        };
      in {
        # perSystem level option definition
        options.cardano-parts = mkOption {
          type = mainPerSystemSubmodule;
        };

        # perSystem level config definition
        config = {
          cardano-parts = mkDefault {};

          packages = {
            inherit
              (cfgPkgs)
              bech32
              cardano-address
              cardano-cli
              cardano-cli-ng
              cardano-db-sync
              cardano-db-tool
              cardano-faucet
              cardano-node
              cardano-node-ng
              cardano-submit-api
              cardano-tracer
              cardano-wallet
              db-analyser
              db-synthesizer
              db-truncater
              metadata-server
              metadata-sync
              metadata-validator-github
              metadata-webhook
              token-metadata-creator
              ;
          };
        };
      });
    };

    config = {
      # Top level config definition
      flake.cardano-parts = mkDefault {};

      flake.legacyPackages = foldl' (legacyPackages: system:
        recursiveUpdate
        legacyPackages {
          ${system}.cardanoLib = flake.config.flake.cardano-parts.pkgs.cardanoLib system;
        }) {}
      flake.config.systems;
    };
  }
