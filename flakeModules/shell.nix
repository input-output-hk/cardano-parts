# flakeModule: inputs.cardano-parts.flakeModules.shell
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   perSystem.cardano-parts.shell.defaultFormatterCfg
#   perSystem.cardano-parts.shell.defaultFormatterCheck
#   perSystem.cardano-parts.shell.defaultFormatterHook
#   perSystem.cardano-parts.shell.defaultFormatterPkg
#   perSystem.cardano-parts.shell.defaultHooks
#   perSystem.cardano-parts.shell.defaultLintPkg
#   perSystem.cardano-parts.shell.defaultShell
#   perSystem.cardano-parts.shell.defaultVars
#   perSystem.cardano-parts.shell.enableFormatter
#   perSystem.cardano-parts.shell.enableHooks
#   perSystem.cardano-parts.shell.enableLint
#   perSystem.cardano-parts.shell.enableVars
#   perSystem.cardano-parts.shell.extraPkgs
#   perSystem.cardano-parts.shell.pkgGroup.<...>
#
# Attributes optionally configured on flakeModule import depending on above config:
#   perSystem.checks.<lint|treefmt>
#   perSystem.devShells.cardano-parts-<...|[default]>
#   perSystem.formatter
#
# Tips:
#   * If config.cardano-parts.shell.defaultShell is not set, no default devShell is defined
#   * DevShells for each cardano-parts package group are available: devShells.cardano-parts-<...>
#   * DevShell hooks, vars, formatter and lint checks are enabled by default in the cardano-parts devShells
#   * Importers may use perSystem scope config.cardano-parts.shell.pkgGroup.<...> defns for mkShell composition
#   * perSystem attrs are simply accessed through [config.]<...> from within system module context
#   * flake level attrs are accessed from flake at [config.]flake.cardano-parts.shell.<...>
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
      cfgShell = cfg.shell;
      cfgPkgGroup = cfgShell.pkgGroup;
      cfgPkgs = cfg.pkgs;
      flakeCfg = flake.config.flake.cardano-parts;

      withLocal = withSystem system;
      treefmtEval = localFlake.inputs.treefmt-nix.lib.evalModule pkgs cfgShell.defaultFormatterCfg;
      isPartsRepo = "${lib.getExe pkgs.gnugrep} -qiE 'cardano[- ]parts' flake.nix &> /dev/null";

      mainSubmodule = submodule {
        options = {
          shell = mkOption {
            type = shellSubmodule;
            description = mdDoc "Cardano-parts shell options";
            default = {};
          };
        };
      };

      shellSubmodule = submodule {
        options = {
          defaultShell = mkOption {
            type = nullOr (enum (builtins.attrNames cfgPkgGroup));
            description = mdDoc "The cardano-parts shell to set as default, if desired.";
            default = null;
          };

          defaultFormatterCheck = mkOption {
            type = package;
            description = mdDoc "The cardano-parts default formatter check package.";
            default = treefmtEval.config.build.check flake.self;
          };

          defaultFormatterCfg = mkOption {
            type = attrsOf anything;
            description = mdDoc "The cardano-parts default formatter config.";
            default = {
              projectRootFile = "flake.nix";
              programs.alejandra.enable = true;
            };
          };

          defaultFormatterHook = mkOption {
            type = str;
            description = mdDoc "The cardano-parts default formatter hook.";
            default = ''
              if ${isPartsRepo}; then
                ln -sf ${treefmtEval.config.build.configFile} treefmt.toml
              fi
            '';
          };

          defaultFormatterPkg = mkOption {
            type = package;
            description = mdDoc "The cardano-parts default flake formatter package.";
            default = treefmtEval.config.build.wrapper;
          };

          defaultHooks = mkOption {
            type = str;
            description = mdDoc "The cardano-parts default git and shell hooks.";
            default = ''
              if ${isPartsRepo} && [ -d .git/hooks ]; then
                ln -sf ${lib.getExe (withLocal ({config, ...}: config.packages.pre-push))} .git/hooks/
              fi
            '';
          };

          defaultLintPkg = mkOption {
            type = package;
            description = mdDoc "The cardano-parts default lint package.";
            default =
              pkgs.runCommand "lint" {
                nativeBuildInputs = with pkgs; [
                  deadnix
                  statix
                ];
              } ''
                set -euo pipefail

                cd ${self}
                deadnix -f
                statix check
                touch $out
              '';
          };

          defaultVars = mkOption {
            type = attrs;
            description = mdDoc "The cardano-parts default shell env vars.";
            default = {
              AWS_PROFILE = flakeCfg.cluster.profile;
              AWS_REGION = flakeCfg.cluster.region;
              KMS = flakeCfg.cluster.kms;
              SSH_CONFIG_FILE = ".ssh_config";
            };
          };

          enableFormatter = mkOption {
            type = bool;
            description = mdDoc "Enable default cardano-parts formatter in the devShells.";
            default = true;
          };

          enableHooks = mkOption {
            type = bool;
            description = mdDoc "Enable default cardano-parts git and shell hooks in the devShells.";
            default = true;
          };

          enableLint = mkOption {
            type = bool;
            description = mdDoc "Enable default cardano-parts lint check in the devShells.";
            default = true;
          };

          enableVars = mkOption {
            type = bool;
            description = mdDoc "Enable default cardano-parts env vars in the devShells.";
            default = true;
          };

          extraPkgs = mkOption {
            type = listOf package;
            description = mdDoc "Extra packages which are added to all devShells.";
            default = [];
          };

          pkgGroup = mkOption {
            type = pkgGroupSubmodule;
            description = mdDoc "Package groups for mkShell composition";
            default = {};
          };
        };
      };

      pkgGroupSubmodule = submodule {
        options = {
          min = mkOption {
            type = listOf package;
            description = mdDoc "Minimal package group";
            default = with pkgs; [
              deadnix
              just
              nushell
              statix
              xxd
            ];
          };

          dev = mkOption {
            type = listOf package;
            description = mdDoc "Developer package group";
            default =
              cfgPkgGroup.min
              ++ localFlake.inputs.haskell-nix.devShells.${system}.default.buildInputs
              ++ (with pkgs; [
                ghcid
              ]);
          };

          test = mkOption {
            type = listOf package;
            description = mdDoc "Testing package group";
            default =
              cfgPkgGroup.min
              ++ (with pkgs;
                with cfgPkgs; [
                  b2sum
                  haskellPackages.cbor-tool
                  bech32
                  cardano-address
                  cardano-cli
                  cardano-cli-ng
                  cardano-node
                  cardano-node-ng
                  cardano-wallet
                  db-analyser
                  db-synthesizer
                  db-truncater
                  token-metadata-creator
                  # TODO:
                  # update-cabal-source-repo-checksums
                ]);
          };

          ops = mkOption {
            type = listOf package;
            description = mdDoc "Operations package group";
            default =
              cfgPkgGroup.test
              ++ (with pkgs;
                with localFlake.packages.${system}; [
                  awscli2
                  localFlake.inputs.colmena.packages.${system}.colmena
                  rain
                  sops
                  terraform
                  wireguard-tools
                ]);
          };

          all = mkOption {
            type = listOf package;
            description = mdDoc "Kitchen sink package group";
            default =
              cfgPkgGroup.dev
              ++ cfgPkgGroup.ops;
          };
        };
      };
    in {
      # perSystem level option definition
      options.cardano-parts = mkOption {
        type = mainSubmodule;
      };

      config = {
        cardano-parts = mkDefault {};

        devShells = let
          mkShell = pkgGroup:
            pkgs.mkShell ({
                packages = cfgPkgGroup.${pkgGroup} ++ cfgShell.extraPkgs;
                shellHook =
                  # Add optional git/shell and formatter hooks
                  optionalString cfgShell.enableHooks cfgShell.defaultHooks
                  + optionalAttrs cfgShell.enableFormatter cfgShell.defaultFormatterHook;
              }
              # Add optional default shell environment variables
              // optionalAttrs cfgShell.enableVars cfgShell.defaultVars);
        in
          # Add default devShells composed of available flakeModule package groups
          # Add optional defaultShell
          foldl (shells: n: recursiveUpdate shells {"cardano-parts-${n}" = mkShell n;}) {} (builtins.attrNames cfgPkgGroup)
          // optionalAttrs (cfgShell.defaultShell != null) {default = config.devShells."cardano-parts-${cfgShell.defaultShell}";};

        # Add optional checks: lint, formatter
        checks =
          lib.optionalAttrs cfgShell.enableLint {lint = cfgShell.defaultLintPkg;}
          // lib.optionalAttrs cfgShell.enableFormatter {treefmt = cfgShell.defaultFormatterCheck;};

        # Add optional formatter
        formatter = lib.optionalAttrs cfgShell.enableFormatter cfgShell.defaultFormatterPkg;
      };
    });
  };
}
