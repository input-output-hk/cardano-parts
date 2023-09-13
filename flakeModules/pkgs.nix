# flakeModule: inputs.cardano-parts.flakeModules.pkgs
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.pkgs.special.cardanoLib
#   flake.cardano-parts.pkgs.special.cardanoLibNg
#   flake.cardano-parts.pkgs.special.cardano-node-pkgs
#   flake.cardano-parts.pkgs.special.cardano-node-pkgs-ng
#   flake.cardano-parts.pkgs.special.cardano-node-service
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
#   perSystem.cardano-parts.pkgs.cardano-submit-api-ng
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
  withSystem,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mdDoc mkOption;
  inherit (lib.types) anything attrsOf functionTo package str submodule;

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
      special = mkOption {
        type = specialPkgsSubmodule;
        description = mdDoc "Cardano-parts special package options";
        default = {};
      };
    };
  };

  specialPkgsSubmodule = submodule {
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

          The definition must be a function of system.
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

      cardanoLibNg = mkOption {
        type = anything;
        description = mdDoc ''
          The cardano-parts system dependent default package for cardanoLibNg.

          This is the same as the cardanoLib option with the exception that the
          iohk-nix-ng flake input is used to obtain cardanoLib.

          The definition must be a function of system.
        '';
        default = system:
          (import localFlake.inputs.nixpkgs {
            inherit system;
            overlays = map (
              overlay: localFlake.inputs.iohk-nix-ng.overlays.${overlay}
            ) (builtins.attrNames localFlake.inputs.iohk-nix-ng.overlays);
          })
          .cardanoLib;
      };

      cardano-node-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          The cardano-parts default cardano-node-pkgs attrset.

          Used in cardano-node nixos service as an alternative to specifying
          packages individually.  This is an attrset of packages and not a proper
          package derivation.

          The definition must be a function of system.
        '';
        default = system: {
          cardano-cli = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-cli);
          cardano-node = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node);
          cardano-submit-api = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api);
          cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
        };
      };

      cardano-node-pkgs-ng = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          The cardano-parts default cardano-node-pkgs-ng attrset.

          This is the same as the cardano-node-pkgs option with the exception that the
          *-ng flake inputs are used for composing the package set.

          The definition must be a function of system.
        '';
        default = system: {
          cardano-cli = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-cli-ng);
          cardano-node = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node-ng);
          cardano-submit-api = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api-ng);
          cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
        };
      };

      cardano-node-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-node-service import path string.";
        default = "${localFlake.inputs.cardano-node-service}/nix/nixos";
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
        caPkgs = localFlake.inputs.capkgs.packages.${system};

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
            meta.mainProgram = name;
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
            (mkPkg "bech32" caPkgs.bech32-exe-bech32-1-1-2-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-address" caPkgs.cardano-addresses-cli-exe-cardano-address-3-12-0-cardano-foundation-cardano-wallet-v2023-07-18)
            (mkPkg "cardano-cli" caPkgs.cardano-cli-exe-cardano-cli-8-1-2-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-cli-ng" caPkgs.cardano-cli-exe-cardano-cli-8-5-0-0-input-output-hk-cardano-node-8-2-1-pre)
            (mkPkg "cardano-db-sync" caPkgs.cardano-db-sync-exe-cardano-db-sync-13-1-1-3-input-output-hk-cardano-db-sync-13-1-1-3)
            (mkPkg "cardano-db-tool" caPkgs.cardano-db-tool-exe-cardano-db-tool-13-1-1-3-input-output-hk-cardano-db-sync-13-1-1-3)
            # TODO: Add faucet repo to capkgs
            # (mkPkg "cardano-faucet" localFlake.inputs.cardano-faucet.packages.${system}."cardano-faucet:exe:cardano-faucet")
            (mkPkg "cardano-node" caPkgs.cardano-node-exe-cardano-node-8-1-2-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-node-ng" caPkgs.cardano-node-exe-cardano-node-8-2-1-input-output-hk-cardano-node-8-2-1-pre)
            (mkPkg "cardano-submit-api" caPkgs.cardano-submit-api-exe-cardano-submit-api-3-1-2-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-submit-api-ng" caPkgs.cardano-submit-api-exe-cardano-submit-api-3-1-3-input-output-hk-cardano-node-8-2-1-pre)
            (mkPkg "cardano-tracer" caPkgs.cardano-tracer-exe-cardano-tracer-0-1-0-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-wallet" caPkgs.cardano-wallet-2023-7-18-cardano-foundation-cardano-wallet-v2023-07-18)
            (mkPkg "db-analyser" caPkgs.ouroboros-consensus-cardano-exe-db-analyser-0-6-0-0-input-output-hk-cardano-node-8-1-2)
            (mkPkg "db-synthesizer" caPkgs.ouroboros-consensus-cardano-exe-db-synthesizer-0-6-0-0-input-output-hk-cardano-node-8-1-2)
            (mkPkg "db-truncater" caPkgs.ouroboros-consensus-cardano-exe-db-truncater-0-7-0-0-input-output-hk-cardano-node-8-2-1-pre)
            # TODO: Add offchain-metadata-tools repo to capkgs
            # (mkPkg "metadata-server" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-server)
            # (mkPkg "metadata-sync" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-sync)
            # (mkPkg "metadata-validator-github" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-validator-github)
            # (mkPkg "metadata-webhook" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.metadata-webhook)
            # (mkPkg "token-metadata-creator" localFlake.inputs.offchain-metadata-tools.${system}.app.packages.token-metadata-creator)
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
            # TODO:
            # cardano-faucet
            # metadata-server
            # metadata-sync
            # metadata-validator-github
            # metadata-webhook
            # token-metadata-creator
            inherit
              (cfgPkgs)
              bech32
              cardano-address
              cardano-cli
              cardano-db-sync
              cardano-db-tool
              cardano-node
              cardano-submit-api
              cardano-tracer
              cardano-wallet
              db-analyser
              db-synthesizer
              db-truncater
              ;

            # The `-ng` variants provide wrapped derivations to avoid cli collision with their non-wrapped, non-ng counterparts.
            cardano-cli-ng = mkWrapper "cardano-cli-ng" cfgPkgs.cardano-cli-ng;
            cardano-node-ng = mkWrapper "cardano-node-ng" cfgPkgs.cardano-node-ng;
            cardano-submit-api-ng = mkWrapper "cardano-submit-api-ng" cfgPkgs.cardano-submit-api-ng;
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
          ${system}.cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
        }) {}
      flake.config.systems;
    };
  }
