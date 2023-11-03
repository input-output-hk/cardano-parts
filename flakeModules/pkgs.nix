# flakeModule: inputs.cardano-parts.flakeModules.pkgs
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.pkgs.special.cardanoLib
#   flake.cardano-parts.pkgs.special.cardanoLibNg
#   flake.cardano-parts.pkgs.special.cardano-db-sync-schema
#   flake.cardano-parts.pkgs.special.cardano-db-sync-schema-ng
#   flake.cardano-parts.pkgs.special.cardano-db-sync-pkgs
#   flake.cardano-parts.pkgs.special.cardano-db-sync-pkgs-ng
#   flake.cardano-parts.pkgs.special.cardano-db-sync-service
#   flake.cardano-parts.pkgs.special.cardano-faucet-service
#   flake.cardano-parts.pkgs.special.cardano-node-pkgs
#   flake.cardano-parts.pkgs.special.cardano-node-pkgs-ng
#   flake.cardano-parts.pkgs.special.cardano-node-service
#   flake.cardano-parts.pkgs.special.cardano-smash-service
#   perSystem.cardano-parts.pkgs.bech32
#   perSystem.cardano-parts.pkgs.cardano-address
#   perSystem.cardano-parts.pkgs.cardano-cli
#   perSystem.cardano-parts.pkgs.cardano-cli-ng
#   perSystem.cardano-parts.pkgs.cardano-db-sync
#   perSystem.cardano-parts.pkgs.cardano-db-sync-ng
#   perSystem.cardano-parts.pkgs.cardano-db-tool
#   perSystem.cardano-parts.pkgs.cardano-faucet
#   perSystem.cardano-parts.pkgs.cardano-faucet-ng
#   perSystem.cardano-parts.pkgs.cardano-node
#   perSystem.cardano-parts.pkgs.cardano-node-ng
#   perSystem.cardano-parts.pkgs.cardano-smash
#   perSystem.cardano-parts.pkgs.cardano-smash-ng
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
  inherit (lib) filterAttrs init last mdDoc mkOption updateManyAttrsByPath;
  inherit (lib.types) anything attrsOf functionTo package path str submodule;

  removeByPath = pathList:
    updateManyAttrsByPath [
      {
        path = init pathList;
        update = filterAttrs (n: _: n != (last pathList));
      }
    ];

  mkCardanoLib = system: flakeRef:
  # Remove the dead testnet environment until it is removed from iohk-nix
    removeByPath ["environments" "testnet"]
    (import localFlake.inputs.nixpkgs {
      inherit system;
      overlays = map (
        overlay: flakeRef.overlays.${overlay}
      ) (builtins.attrNames flakeRef.overlays);
    })
    .cardanoLib;

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
        default = system: mkCardanoLib system localFlake.inputs.iohk-nix;
      };

      cardanoLibNg = mkOption {
        type = anything;
        description = mdDoc ''
          The cardano-parts system dependent default package for cardanoLibNg.

          This is the same as the cardanoLib option with the exception that the
          iohk-nix-ng flake input is used to obtain cardanoLib.

          The definition must be a function of system.
        '';
        default = system: mkCardanoLib system localFlake.inputs.iohk-nix-ng;
      };

      cardano-db-sync-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          The cardano-parts default cardano-db-sync-pkgs attrset.

          Used in cardano-db-sync nixos related services, such as smash and
          service schema.  This is an attrset of packages and not a proper
          package derivation.

          The definition must be a function of system.
        '';
        default = system: {
          cardanoDbSyncHaskellPackages.cardano-db-tool.components.exes.cardano-db-tool =
            withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-tool);
          cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
          schema = flake.config.flake.cardano-parts.pkgs.special.cardano-db-sync-schema;
        };
      };

      cardano-db-sync-pkgs-ng = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          The cardano-parts default cardano-db-sync-pkgs-ng attrset.

          This is the same as the cardano-db-sync-pkgs option with the exception that the
          *-ng flake inputs or packages are used for composing the package set.

          The definition must be a function of system.
        '';
        default = system: {
          cardanoDbSyncHaskellPackages.cardano-db-tool.components.exes.cardano-db-tool =
            withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-tool-ng);
          cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
          schema = flake.config.flake.cardano-parts.pkgs.special.cardano-db-sync-schema-ng;
        };
      };

      cardano-db-sync-schema = mkOption {
        type = path;
        description = mdDoc ''
          The cardano-parts default cardano-db-sync-schema path.

          Used in cardano-db-sync to provide migration schema.
          Since only packages are provided with capkgs, a schema
          reference needs to be provided separately.
        '';
        default = "${localFlake.inputs.cardano-db-sync-schema}/schema";
      };

      cardano-db-sync-schema-ng = mkOption {
        type = path;
        description = mdDoc ''
          The cardano-parts default cardano-db-sync-schema-ng path.

          This is the same as the cardano-db-sync-schema option with the exception that the
          *-ng flake inputs or packages are used for composing the option.
        '';
        default = "${localFlake.inputs.cardano-db-sync-schema-ng}/schema";
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
          *-ng flake inputs or packages are used for composing the package set.

          The definition must be a function of system.
        '';
        default = system: {
          cardano-cli = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-cli-ng);
          cardano-node = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node-ng);
          cardano-submit-api = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api-ng);
          cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
        };
      };

      cardano-db-sync-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-db-sync-service import path string.";
        default = "${localFlake.inputs.cardano-db-sync-service}/nix/nixos/cardano-db-sync-service.nix";
      };

      # TODO: Module import fixup for local services
      cardano-faucet-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-faucet-service import path string.";
        # default = localFlake.nixosModules.service-cardano-faucet;
        default = "${localFlake}/flake/nixosModules/service-cardano-faucet.nix";
      };

      cardano-node-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-node-service import path string.";
        default = "${localFlake.inputs.cardano-node-service}/nix/nixos";
      };

      cardano-smash-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-smash-service import path string.";
        default = "${localFlake.inputs.cardano-db-sync-service}/nix/nixos/smash-service.nix";
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

        mkWrapper = name: pkg: let
          pkgName = pkg.meta.mainProgram or (getName pkg);
        in
          with pkgs;
            runCommand name
            {
              allowSubstitutes = false;
              executable = true;
              preferLocalBuild = true;

              text = ''
                #!${runtimeShell}
                exec ${getExe pkg} "$@"
              '';

              checkPhase = ''
                ${stdenv.shellDryRun} "$target"
              '';

              passAsFile = ["text"];

              meta = {
                description = "Wrapper for ${getName pkg}${
                  if getVersion pkg != ""
                  then " (${getVersion pkg})"
                  else ""
                }";
                mainProgram = name;
              };
              version = getVersion pkg;
            }
            ''
              target=$out${lib.escapeShellArg "/bin/${name}"}
              mkdir -p "$(dirname "$target")"

              if [ -e "$textPath" ]; then
                mv "$textPath" "$target"
              else
                echo -n "$text" > "$target"
              fi

              if [ -n "$executable" ]; then
                chmod +x "$target"
              fi

              # Preserve nixos bash and zsh command completions for the wrapped program
              # Remove fd overrideAttrs mod to avoid mainProgram warn once nixpkgs >= 23.11
              if [ -d "${pkg}/share" ]; then
                cp -r "${pkg}/share" $out
                chmod -R +w $out/share
                ${getExe (fd.overrideAttrs (_: {meta.mainProgram = "fd";}))} --type f . ${pkgName} $out/share --exec bash -c '
                  ${getExe gnused} -i "/\(COMPREPLY=\|completions=\)/ s#${pkgName}#${getExe pkg}#g" {}
                  ${getExe gnused} -i "/\(COMPREPLY=\|completions=\)/! s#${pkgName}#${pkgName}-ng#g" {}
                  mv {} {}-ng
                '
              fi

              eval "$checkPhase"
            '';

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
            # TODO: Fix the missing meta/version info upstream
            (mkPkg "bech32" caPkgs.bech32-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-address" caPkgs.cardano-address-cardano-foundation-cardano-wallet-v2023-07-18)
            (mkPkg "cardano-cli" (caPkgs.cardano-cli-input-output-hk-cardano-node-8-1-2 // {version = "8.1.2";}))
            (mkPkg "cardano-cli-ng" (caPkgs.cardano-cli-input-output-hk-cardano-node-8-6-0-pre // {version = "8.13.0.0";}))
            (mkPkg "cardano-db-sync" (caPkgs.cardano-db-sync-input-output-hk-cardano-db-sync-13-1-1-3 // {exeName = "cardano-db-sync";}))
            (mkPkg "cardano-db-sync-ng" (caPkgs.cardano-db-sync-input-output-hk-cardano-db-sync-sancho-2-2-0 // {exeName = "cardano-db-sync";}))
            (mkPkg "cardano-db-tool" caPkgs.cardano-db-tool-input-output-hk-cardano-db-sync-13-1-1-3)
            (mkPkg "cardano-db-tool-ng" caPkgs.cardano-db-tool-input-output-hk-cardano-db-sync-sancho-2-2-0)
            (mkPkg "cardano-faucet" caPkgs."\"cardano-faucet:exe:cardano-faucet\"-input-output-hk-cardano-faucet-master")
            (mkPkg "cardano-faucet-ng" caPkgs."\"cardano-faucet:exe:cardano-faucet\"-input-output-hk-cardano-faucet-master")
            (mkPkg "cardano-node" (caPkgs.cardano-node-input-output-hk-cardano-node-8-1-2 // {version = "8.1.2";}))
            (mkPkg "cardano-node-ng" (caPkgs.cardano-node-input-output-hk-cardano-node-8-6-0-pre // {version = "8.6.0-pre";}))
            (mkPkg "cardano-smash" caPkgs.cardano-smash-server-no-basic-auth-input-output-hk-cardano-db-sync-13-1-1-3)
            (mkPkg "cardano-smash-ng" caPkgs.cardano-smash-server-no-basic-auth-input-output-hk-cardano-db-sync-sancho-2-2-0)
            (mkPkg "cardano-submit-api" caPkgs.cardano-submit-api-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-submit-api-ng" caPkgs.cardano-submit-api-input-output-hk-cardano-node-8-6-0-pre)
            (mkPkg "cardano-tracer" caPkgs.cardano-tracer-input-output-hk-cardano-node-8-1-2)
            (mkPkg "cardano-wallet" (caPkgs.cardano-wallet-cardano-foundation-cardano-wallet-v2023-07-18
              // {
                pname = "cardano-wallet";
                meta.description = "HTTP server and command-line for managing UTxOs and HD wallets in Cardano.";
              }))
            (mkPkg "db-analyser" caPkgs.db-analyser-input-output-hk-cardano-node-8-1-2)
            (mkPkg "db-analyser-ng" caPkgs.db-analyser-input-output-hk-cardano-node-8-6-0-pre)
            (mkPkg "db-synthesizer" caPkgs.db-synthesizer-input-output-hk-cardano-node-8-1-2)
            (mkPkg "db-synthesizer-ng" caPkgs.db-synthesizer-input-output-hk-cardano-node-8-6-0-pre)
            (mkPkg "db-truncater" caPkgs.db-truncater-input-output-hk-cardano-node-8-2-0-pre)
            (mkPkg "db-truncater-ng" caPkgs.db-truncater-input-output-hk-cardano-node-8-6-0-pre)
            (mkPkg "metadata-server" caPkgs.metadata-server-input-output-hk-offchain-metadata-tools-feat-add-password-to-db-conn-string)
            (mkPkg "metadata-sync" caPkgs.metadata-sync-input-output-hk-offchain-metadata-tools-feat-add-password-to-db-conn-string)
            (mkPkg "metadata-validator-github" caPkgs.metadata-validator-github-input-output-hk-offchain-metadata-tools-feat-add-password-to-db-conn-string)
            (mkPkg "metadata-webhook" caPkgs.metadata-webhook-input-output-hk-offchain-metadata-tools-feat-add-password-to-db-conn-string)
            (mkPkg "token-metadata-creator" (recursiveUpdate caPkgs.token-metadata-creator-input-output-hk-offchain-metadata-tools-feat-add-password-to-db-conn-string {meta.mainProgram = "token-metadata-creator";}))
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
              cardano-db-sync
              cardano-db-tool
              cardano-faucet
              cardano-node
              cardano-smash
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

            # The `-ng` variants provide wrapped derivations to avoid cli collision with their non-wrapped, non-ng counterparts.
            cardano-cli-ng = mkWrapper "cardano-cli-ng" cfgPkgs.cardano-cli-ng;
            cardano-db-sync-ng = mkWrapper "cardano-db-sync-ng" cfgPkgs.cardano-db-sync-ng;
            cardano-db-tool-ng = mkWrapper "cardano-db-tool-ng" cfgPkgs.cardano-db-tool-ng;
            cardano-faucet-ng = mkWrapper "cardano-faucet-ng" cfgPkgs.cardano-faucet-ng;
            cardano-node-ng = mkWrapper "cardano-node-ng" cfgPkgs.cardano-node-ng;
            cardano-smash-ng = mkWrapper "cardano-smash-ng" cfgPkgs.cardano-smash-ng;
            cardano-submit-api-ng = mkWrapper "cardano-submit-api-ng" cfgPkgs.cardano-submit-api-ng;
            db-analyser-ng = mkWrapper "db-analyser-ng" cfgPkgs.db-analyser-ng;
            db-synthesizer-ng = mkWrapper "db-synthesizer-ng" cfgPkgs.db-synthesizer-ng;
            db-truncater-ng = mkWrapper "db-truncater-ng" cfgPkgs.db-truncater-ng;
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
