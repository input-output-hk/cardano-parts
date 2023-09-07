# flakeModule: inputs.cardano-parts.flakeModules.shell
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   perSystem.cardano-parts.shell.global.defaultShell
#   perSystem.cardano-parts.shell.<global|<id>>.defaultFormatterCfg
#   perSystem.cardano-parts.shell.<global|<id>>.defaultFormatterCheck
#   perSystem.cardano-parts.shell.<global|<id>>.defaultFormatterHook
#   perSystem.cardano-parts.shell.<global|<id>>.defaultFormatterPkg
#   perSystem.cardano-parts.shell.<global|<id>>.defaultHooks
#   perSystem.cardano-parts.shell.<global|<id>>.defaultLintPkg
#   perSystem.cardano-parts.shell.<global|<id>>.defaultVars
#   perSystem.cardano-parts.shell.<global|<id>>.enableFormatter
#   perSystem.cardano-parts.shell.<global|<id>>.enableHooks
#   perSystem.cardano-parts.shell.<global|<id>>.enableLint
#   perSystem.cardano-parts.shell.<global|<id>>.enableVars
#   perSystem.cardano-parts.shell.<global|<id>>.extraPkgs
#   perSystem.cardano-parts.shell.<global|<id>>.pkgs
#
# Attributes optionally configured on flakeModule import depending on above config:
#   perSystem.checks.<lint|treefmt>
#   perSystem.devShells.<[default]|<id>>
#   perSystem.formatter
#
# Tips:
#   * If config.cardano-parts.shell.global.defaultShell is not set, no default devShell is defined
#   * DevShell hooks, vars, formatter and lint checks are enabled by default globally
#   * Devshell declared package lists merge with globally defined package lists (ex: pkgs, extraPkgs options)
#   * Devshell declared hooks, formatter and env var options, if defined, will override the corresponding globally defined options
#   * Importers may use perSystem scope config.cardano-parts.shell.<global|<id>>.<pkgs|extraPkgs> defns for mkShell composition
#   * Nix flake checks and formatter are configured only through the global options (ex: lint and treefmt)
#   * perSystem attrs are simply accessed through [config.]<...> from within system module context
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
  inherit (lib.types) anything attrs attrsOf bool enum nullOr listOf package str submodule;
in
  with lib; {
    options = {
      perSystem = mkPerSystemOption ({
        config,
        pkgs,
        system,
        ...
      }: let
        cfg = config.cardano-parts;
        cfgShell = cfg.shell;
        cfgPkgs = cfg.pkgs;
        flakeCfg = flake.config.flake.cardano-parts;

        withLocal = withSystem system;
        treefmtEval = localFlake.inputs.treefmt-nix.lib.evalModule pkgs cfgShell.global.defaultFormatterCfg;
        isPartsRepo = "${getExe pkgs.gnugrep} -qiE 'cardano[- ]parts' flake.nix &> /dev/null";

        globalDefault = isGlobal: default:
          if isGlobal
          then default
          else null;

        globalType = isGlobal: type:
          if isGlobal
          then type
          else nullOr type;

        definedIds = builtins.filter (id: !(builtins.elem id ["global"])) (builtins.attrNames cfgShell);

        mkCommonShellOptions = {
          isGlobal,
          extraCfg ? {},
        }:
          {
            defaultFormatterCheck = mkOption {
              type = globalType isGlobal package;
              description = mdDoc "The cardano-parts default formatter check package.";
              default = globalDefault isGlobal (treefmtEval.config.build.check flake.self);
            };

            defaultFormatterCfg = mkOption {
              type = globalType isGlobal (attrsOf anything);
              description = mdDoc "The cardano-parts default formatter config.";
              default = globalDefault isGlobal {
                projectRootFile = "flake.nix";
                programs.alejandra.enable = true;
              };
            };

            defaultFormatterHook = mkOption {
              type = globalType isGlobal str;
              description = mdDoc "The cardano-parts default formatter hook.";
              default = globalDefault isGlobal ''
                if ${isPartsRepo}; then
                  ln -sf ${treefmtEval.config.build.configFile} treefmt.toml
                fi
              '';
            };

            defaultFormatterPkg = mkOption {
              type = globalType isGlobal package;
              description = mdDoc "The cardano-parts default flake formatter package.";
              default = globalDefault isGlobal treefmtEval.config.build.wrapper;
            };

            defaultHooks = mkOption {
              type = globalType isGlobal str;
              description = mdDoc "The cardano-parts default git and shell hooks.";
              default = globalDefault isGlobal ''
                if ${isPartsRepo} && [ -d .git/hooks ]; then
                  ln -sf ${getExe (withLocal ({config, ...}: config.packages.pre-push))} .git/hooks/
                fi
              '';
            };

            defaultLintPkg = mkOption {
              type = globalType isGlobal package;
              description = mdDoc "The cardano-parts default lint package.";
              default = globalDefault isGlobal (
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
                ''
              );
            };

            defaultVars = mkOption {
              type = globalType isGlobal attrs;
              description = mdDoc "The cardano-parts default devShell env vars.";
              default = globalDefault isGlobal {
                AWS_PROFILE = flakeCfg.cluster.profile;
                AWS_REGION = flakeCfg.cluster.region;
                KMS = flakeCfg.cluster.kms;
                SSH_CONFIG_FILE = ".ssh_config";
              };
            };

            enableFormatter = mkOption {
              type = globalType isGlobal bool;
              description = mdDoc "Enable default cardano-parts formatter in the devShells.";
              default = globalDefault isGlobal true;
            };

            enableHooks = mkOption {
              type = globalType isGlobal bool;
              description = mdDoc "Enable default cardano-parts git and shell hooks in the devShells.";
              default = globalDefault isGlobal true;
            };

            enableLint = mkOption {
              type = globalType isGlobal bool;
              description = mdDoc "Enable default cardano-parts lint check in the devShells.";
              default = globalDefault isGlobal true;
            };

            enableVars = mkOption {
              type = globalType isGlobal bool;
              description = mdDoc "Enable default cardano-parts env vars in the devShells.";
              default = globalDefault isGlobal true;
            };

            extraPkgs = mkOption {
              type = listOf package;
              description = mdDoc "Extra packages.";
              default = [];
            };

            pkgs = mkOption {
              type = listOf package;
              description = mdDoc "Packages.";
              default = [];
            };
          }
          // extraCfg;

        mkShellSubmodule = {
          isGlobal,
          id,
          description,
          extraCfg ? {},
        }: {
          ${id} = mkOption {
            inherit description;
            type = submodule {
              options = mkCommonShellOptions {inherit isGlobal extraCfg;};
            };
            default = {};
          };
        };

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
          # Set global devShell options
          options =
            mkShellSubmodule {
              isGlobal = true;
              id = "global";
              description = mdDoc "The cardano-parts devShell global configuration options.";
              extraCfg = {
                defaultShell = mkOption {
                  type = nullOr (enum definedIds);
                  description = mdDoc "The cardano-parts devShell to set as default, if desired.";
                  default = null;
                };

                pkgs = mkOption {
                  default = map (id: config.packages."menu-${id}") definedIds;
                };
              };
            }
            # Set per devShell options
            // (foldl' (acc: shellCfg: recursiveUpdate acc (mkShellSubmodule ({isGlobal = false;} // shellCfg))) {} [
              {
                id = "min";
                description = mdDoc "Minimal devShell";
                extraCfg.pkgs = mkOption {
                  default = with pkgs; [
                    deadnix
                    just
                    nushell
                    statix
                    xxd
                  ];
                };
              }
              {
                id = "dev";
                description = mdDoc "Developer devShell";
                extraCfg.pkgs = mkOption {
                  default =
                    config.cardano-parts.shell.min.pkgs
                    ++ localFlake.inputs.haskell-nix.devShells.${system}.default.buildInputs
                    ++ (with pkgs; [
                      ghcid
                    ]);
                };
              }
              {
                id = "test";
                description = mdDoc "Testing devShell";
                extraCfg.pkgs = mkOption {
                  default =
                    config.cardano-parts.shell.min.pkgs
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
                        # Until offchain-metadata-tools repo is added to capkgs
                        # token-metadata-creator
                        # TODO:
                        # update-cabal-source-repo-checksums
                      ]);
                };
              }
              {
                id = "ops";
                description = mdDoc "Operations devShell";
                extraCfg.pkgs = mkOption {
                  default =
                    config.cardano-parts.shell.test.pkgs
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
              }
              {
                id = "all";
                description = mdDoc "Kitchen sink devShell";
                extraCfg.pkgs = mkOption {
                  default =
                    config.cardano-parts.shell.dev.pkgs
                    ++ config.cardano-parts.shell.ops.pkgs;
                };
              }
            ]);
        };

        # Select between global and perShell scope precedence
        selectScope = id: f: boolCheck: option:
          if cfgShell.${id}.${boolCheck} != null
          then f cfgShell.${id}.${boolCheck} cfgShell.${id}.${option}
          else f cfgShell.global.${boolCheck} cfgShell.global.${option};

        allPkgs = id:
          cfgShell.${id}.pkgs
          ++ cfgShell.${id}.extraPkgs
          ++ cfgShell.global.pkgs
          ++ cfgShell.global.extraPkgs
          ++ [(mkMenuWrapper id)]
          ++ selectScope id optional "enableFormatter" "defaultFormatterPkg";

        mkMenuWrapper = id:
          (pkgs.writeShellScriptBin "menu" ''
            exec ${getExe config.packages."menu-${id}"} "$@"
          '')
          .overrideAttrs (
            _: {
              meta.description = "Wrapper for menu-${id}";
              meta.mainProgram = "menu";
            }
          );

        mkMenu = id: {
          "menu-${id}" =
            (pkgs.writeShellApplication
              {
                name = "menu-${id}";
                runtimeInputs = with pkgs; [lolcat];

                text = let
                  pkgStr = pkg:
                    if getVersion pkg != ""
                    then "${getName pkg} (${getVersion pkg})"
                    else getName pkg;
                  minWidth =
                    head (
                      reverseList (
                        builtins.sort builtins.lessThan (
                          map (pkg: builtins.stringLength pkg.name) (allPkgs id)
                        )
                      )
                    )
                    + 4;
                in ''
                  echo "Cardano Parts DevShell Menu: ${id}" | lolcat
                  echo
                  echo "The following packages are available in the ${id} devShell:"
                  echo
                  echo "${builtins.concatStringsSep "\n" (map (pkg:
                    if builtins.hasAttr "description" pkg.meta
                    then pkgStr pkg + fixedWidthString (minWidth - builtins.stringLength (pkgStr pkg)) " " "" + pkg.meta.description
                    else pkgStr pkg)
                  (allPkgs id))}"
                  echo
                  echo
                  echo "Other cardano-parts devShells available are:"
                  echo "${concatMapStringsSep "\n" (id: "  ${id} (info: menu-${id})") definedIds}"
                  echo
                '';
              })
            .overrideAttrs (
              _: {
                meta.description = "Cardano parts menu for devShell ${id}";
                meta.mainProgram = "menu-${id}";
              }
            );
        };
      in {
        # perSystem level option definition
        options.cardano-parts = mkOption {
          type = mainSubmodule;
        };

        config = {
          cardano-parts = mkDefault {};

          devShells = let
            mkShell = id:
              pkgs.mkShell ({
                  packages = allPkgs id;
                  shellHook =
                    # Add optional git/shell and formatter hooks
                    selectScope id optionalString "enableHooks" "defaultHooks"
                    + selectScope id optionalAttrs "enableFormatter" "defaultFormatterHook"
                    + ''
                      menu
                    '';
                }
                # Add optional default shell environment variables
                // selectScope id optionalAttrs "enableVars" "defaultVars");
          in
            # Add default devShells composed of available defined cardano-parts.shell.<id> attrsets
            # Add optional defaultShell
            foldl' (shells: id: recursiveUpdate shells {${id} = mkShell id;}) {} definedIds
            // optionalAttrs (cfgShell.global.defaultShell != null) {default = config.devShells.${cfgShell.global.defaultShell};};

          # Add optional checks: lint, formatter
          checks =
            optionalAttrs cfgShell.global.enableLint {lint = cfgShell.global.defaultLintPkg;}
            // optionalAttrs cfgShell.global.enableFormatter {treefmt = cfgShell.global.defaultFormatterCheck;};

          # Add optional formatter
          formatter = optionalAttrs cfgShell.global.enableFormatter cfgShell.global.defaultFormatterPkg;

          # Make devshell menu packages menu-<id>
          packages = foldl' (acc: id: recursiveUpdate acc (mkMenu id)) {} definedIds;
        };
      });
    };
  }
