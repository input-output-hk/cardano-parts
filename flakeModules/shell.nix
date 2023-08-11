# flakeModule: inputs.cardano-parts.flakeModules.shell
#
# Attributes available on flakeModule import:
#   perSystem.cardano-parts.shell.defaultShell
#   perSystem.cardano-parts.shell.defaultHooks
#   perSystem.cardano-parts.shell.defaultVars
#   perSystem.cardano-parts.shell.enableHooks
#   perSystem.cardano-parts.shell.enableVars
#   perSystem.cardano-parts.shell.pkgGroup.<...>
#   perSystem.devShells.cardano-parts-<...|[default]>
#
# Tips:
#   * If config.cardano-parts.shell.default is not set, no default devShell is defined
#   * DevShells for each cardano-parts package group are available: devShells.cardano-parts-<...>
#   * DevShell hooks and vars are enabled by default in the cardano-parts devShells
#   * Importers may use config.cardano-parts.shell.pkgGroup.<...> defns for mkShell composition
#   * perSystem attrs are simply accessed through config.<...> from within system module context
#   * topLevel attrs are accessed from top level config of flake.config.<...> or from shell at .#<...>
localFlake: toplevel @ {
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) foldl mdDoc mkDefault mkIf mkOption optionalAttrs optionalString recursiveUpdate types;
  inherit (types) attrs bool enum nullOr listOf package str submodule;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      inputs',
      pkgs,
      self',
      system,
      ...
    }: let
      cfg = config.cardano-parts;
      cfgShell = cfg.shell;
      cfgPkg = cfgShell.pkgGroup;
      topCfg = toplevel.config.flake.cardano-parts;
      withLocal = localRef: localFlake.withSystem system localRef;

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
            type = nullOr (enum (builtins.attrNames cfgPkg));
            description = mdDoc "The cardano-parts shell to set as default, if desired.";
            default = null;
          };

          # defaultFormatter = mkOption {
          #   type = str;
          #   description = mdDoc "The cardano-parts default formatter.";
          #   default = ''
          #     ln -sf ${config.treefmt.build.configFile} treefmt.toml
          #   '';
          # };

          defaultHooks = mkOption {
            type = str;
            description = mdDoc "The cardano-parts default git and shell hooks.";
            default = ''
              ln -sf ${lib.getExe self'.packages.pre-push} .git/hooks/
            '';
          };

          defaultVars = mkOption {
            type = attrs;
            description = mdDoc "The cardano-parts default shell env vars.";
            default = {
              SSH_CONFIG_FILE = ".ssh_config";
              KMS = topCfg.cluster.kms;
              AWS_REGION = topCfg.cluster.region;
              AWS_PROFILE = topCfg.cluster.profile;
            };
          };

          # enableFormatter = mkOption {
          #   type = bool;
          #   description = mdDoc "Enable default cardano-parts formatter in the devShells.";
          #   default = true;
          # };

          enableHooks = mkOption {
            type = bool;
            description = mdDoc "Enable default cardano-parts git and shell hooks in the devShells.";
            default = true;
          };

          enableVars = mkOption {
            type = bool;
            description = mdDoc "Enable default cardano-parts infra mgmt env vars in the devShells.";
            default = true;
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
              cfgPkg.min
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
              cfgPkg.min
              ++ (with pkgs; [
                b2sum
                haskellPackages.cbor-tool
                # TODO:
                # bech32
                # cardano-address
                # cardano-cli
                # cardano-node
                # cardano-wallet
                # db-analyzer
                # db-synthesizer
                # db-truncater
                # update-cabal-source-repo-checksums
                # ...
              ]);
          };

          ops = mkOption {
            type = listOf package;
            description = mdDoc "Operations package group";
            default =
              cfgPkg.test
              ++ (with pkgs; [
                awscli2
                (withLocal ({inputs', ...}: inputs'.colmena.packages.colmena))
                (withLocal ({config, ...}: config.packages.rain))
                (withLocal ({config, ...}: config.packages.terraform))
                sops
                wireguard-tools
              ]);
          };

          all = mkOption {
            type = listOf package;
            description = mdDoc "Kitchen sink package group";
            default =
              cfgPkg.dev
              ++ cfgPkg.ops;
          };
        };
      };
    in {
      _file = ./shell.nix;

      # perSystem level option definition
      options.cardano-parts = mkOption {
        type = mainSubmodule;
      };

      config = {
        cardano-parts = mkDefault {};

        devShells = let
          mkShell = pkgGroup:
            pkgs.mkShell ({
                packages = cfgPkg.${pkgGroup};
                shellHook =
                  optionalString cfgShell.enableHooks cfgShell.defaultHooks;
                # + optionalAttrs cfgShell.enableFormatter cfgShell.defaultFormatter;
              }
              // optionalAttrs cfgShell.enableVars cfgShell.defaultVars);
        in
          foldl (shells: n: recursiveUpdate shells {"cardano-parts-${n}" = mkShell n;}) {} (builtins.attrNames cfgPkg)
          // optionalAttrs (cfgShell.defaultShell != null) {default = config.devShells."cardano-parts-${cfgShell.defaultShell}";};
      };
    });
  };
}
