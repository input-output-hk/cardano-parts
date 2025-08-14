# flakeModule: inputs.cardano-parts.flakeModules.pkgs
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.pkgs.special.blockfrost-platform-service
#   flake.cardano-parts.pkgs.special.cardanoLib
#   flake.cardano-parts.pkgs.special.cardanoLibCustom
#   flake.cardano-parts.pkgs.special.cardanoLibNg
#   flake.cardano-parts.pkgs.special.cardano-db-sync-schema
#   flake.cardano-parts.pkgs.special.cardano-db-sync-schema-ng
#   flake.cardano-parts.pkgs.special.cardano-db-sync-pkgs
#   flake.cardano-parts.pkgs.special.cardano-db-sync-pkgs-ng
#   flake.cardano-parts.pkgs.special.cardano-db-sync-service
#   flake.cardano-parts.pkgs.special.cardano-db-sync-service-ng
#   flake.cardano-parts.pkgs.special.cardano-faucet-service
#   flake.cardano-parts.pkgs.special.cardano-metadata-pkgs
#   flake.cardano-parts.pkgs.special.cardano-metadata-service
#   flake.cardano-parts.pkgs.special.cardano-node-pkgs
#   flake.cardano-parts.pkgs.special.cardano-node-pkgs-ng
#   flake.cardano-parts.pkgs.special.cardano-node-service
#   flake.cardano-parts.pkgs.special.cardano-node-service-ng
#   flake.cardano-parts.pkgs.special.cardano-ogmios-service
#   flake.cardano-parts.pkgs.special.cardano-smash-service
#   flake.cardano-parts.pkgs.special.cardano-smash-service-ng
#   flake.cardano-parts.pkgs.special.cardano-submit-api-service
#   flake.cardano-parts.pkgs.special.cardano-submit-api-service-ng
#   flake.cardano-parts.pkgs.special.cardano-tracer-service
#   flake.cardano-parts.pkgs.special.cardano-tracer-service-ng
#   perSystem.cardano-parts.pkgs.bech32
#   perSystem.cardano-parts.pkgs.blockfrost-platform
#   perSystem.cardano-parts.pkgs.blockperf
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
#   perSystem.cardano-parts.pkgs.cardano-ogmios
#   perSystem.cardano-parts.pkgs.cardano-signer
#   perSystem.cardano-parts.pkgs.cardano-smash
#   perSystem.cardano-parts.pkgs.cardano-smash-ng
#   perSystem.cardano-parts.pkgs.cardano-submit-api
#   perSystem.cardano-parts.pkgs.cardano-submit-api-ng
#   perSystem.cardano-parts.pkgs.cardano-testnet
#   perSystem.cardano-parts.pkgs.cardano-testnet-ng
#   perSystem.cardano-parts.pkgs.cardano-tracer
#   perSystem.cardano-parts.pkgs.cardano-wallet
#   perSystem.cardano-parts.pkgs.cc-sign
#   perSystem.cardano-parts.pkgs.colemena
#   perSystem.cardano-parts.pkgs.db-analyser
#   perSystem.cardano-parts.pkgs.db-synthesizer
#   perSystem.cardano-parts.pkgs.db-truncater
#   perSystem.cardano-parts.pkgs.metadata-server
#   perSystem.cardano-parts.pkgs.metadata-sync
#   perSystem.cardano-parts.pkgs.metadata-validator-github
#   perSystem.cardano-parts.pkgs.metadata-webhook
#   perSystem.cardano-parts.pkgs.mithril-client-cli
#   perSystem.cardano-parts.pkgs.mithril-client-cli-ng
#   perSystem.cardano-parts.pkgs.mithril-signer
#   perSystem.cardano-parts.pkgs.mithril-signer-ng
#   perSystem.cardano-parts.pkgs.orchestrator-cli
#   perSystem.cardano-parts.pkgs.snapshot-converter
#   perSystem.cardano-parts.pkgs.snapshot-converter-ng
#   perSystem.cardano-parts.pkgs.token-metadata-creator
#   perSystem.cardano-parts.pkgs.tx-bundle
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

  removeManyByPath = listofPathLists:
    updateManyAttrsByPath (map (
        pathList: {
          path = init pathList;
          update = filterAttrs (n: _: n != (last pathList));
        }
      )
      listofPathLists);

  mkCardanoLib = system: flakeRef:
  # If dead environments need to be filtered from iohk-nix, add them here
  # as list items of ["environments" "$DEAD_ENV_NAME"].
    removeManyByPath []
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
      blockfrost-platform-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default blockfrost-platform-service import path string.";
        default = "${localFlake.inputs.blockfrost-platform-service}/nix/nixos";
      };

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

      cardanoLibCustom = mkOption {
        type = anything;
        description = mdDoc ''
          The cardano-parts system dependent default package for cardanoLibCustom.

          This is the same as the cardanoLib option with the exception that a
          custom iohk-nix flake input is passed as an arg to obtain cardanoLib.

          The definition must be a function of iohk-nix input and system.
        '';
        default = iohk-nix: system: mkCardanoLib system iohk-nix;
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

      cardano-metadata-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          The cardano-parts default cardano-metadata-pkgs attrset.

          The definition must be a function of system.
        '';
        default = system: {
          metadata-server = withSystem system ({config, ...}: config.cardano-parts.pkgs.metadata-server);
          metadata-sync = withSystem system ({config, ...}: config.cardano-parts.pkgs.metadata-sync);
          metadata-validator-github = withSystem system ({config, ...}: config.cardano-parts.pkgs.metadata-validator-github);
          metadata-webhook = withSystem system ({config, ...}: config.cardano-parts.pkgs.metadata-webhook);
          token-metadata-creator = withSystem system ({config, ...}: config.cardano-parts.pkgs.token-metadata-creator);
        };
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
          cardano-tracer = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-tracer);
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
          cardano-tracer = withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-tracer-ng);
          cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
        };
      };

      cardano-db-sync-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-db-sync-service import path string.";
        default = "${localFlake.inputs.cardano-db-sync-service}/nix/nixos/cardano-db-sync-service.nix";
      };

      cardano-db-sync-service-ng = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-db-sync-service-ng import path string.";
        default = "${localFlake.inputs.cardano-db-sync-service-ng}/nix/nixos/cardano-db-sync-service.nix";
      };

      # TODO: Module import fixup for local services
      cardano-faucet-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-faucet-service import path string.";
        # default = localFlake.nixosModules.service-cardano-faucet;
        default = "${localFlake}/flake/nixosModules/service-cardano-faucet.nix";
      };

      cardano-metadata-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-metadata-service import path string.";
        default = "${localFlake.inputs.cardano-metadata-service}/nix/nixos/default.nix";
      };

      cardano-node-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-node-service import path string.";
        default = "${localFlake.inputs.cardano-node-service}/nix/nixos/cardano-node-service.nix";
      };

      cardano-node-service-ng = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-node-service-ng import path string.";
        default = "${localFlake.inputs.cardano-node-service-ng}/nix/nixos/cardano-node-service.nix";
      };

      cardano-ogmios-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-ogmios-service import path string.";
        default = "${localFlake.inputs.cardano-ogmios-service}/nix/nixos";
      };

      cardano-smash-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-smash-service import path string.";
        default = "${localFlake.inputs.cardano-db-sync-service}/nix/nixos/smash-service.nix";
      };

      cardano-submit-api-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-submit-api-service import path string.";
        default = "${localFlake.inputs.cardano-submit-api-service}/nix/nixos/cardano-submit-api-service.nix";
      };

      cardano-submit-api-service-ng = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-submit-api-service-ng import path string.";
        default = "${localFlake.inputs.cardano-submit-api-service-ng}/nix/nixos/cardano-submit-api-service.nix";
      };

      cardano-tracer-service = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-tracer-service import path string.";
        default = "${localFlake.inputs.cardano-tracer-service}/nix/nixos/cardano-tracer-service.nix";
      };

      cardano-tracer-service-ng = mkOption {
        type = str;
        description = mdDoc "The cardano-parts default cardano-tracer-service-ng import path string.";
        default = "${localFlake.inputs.cardano-tracer-service-ng}/nix/nixos/cardano-tracer-service.nix";
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
              if [ -d "${pkg}/share" ]; then
                cp -r "${pkg}/share" $out
                chmod -R +w $out/share
                ${getExe fd} --type f . ${pkgName} $out/share --exec bash -c '
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

        pkgsSubmodule = let
          credential-manager-release = "IntersectMBO-credential-manager-0-1-5-0-ba221bd";
          dbsync-release = "input-output-hk-cardano-db-sync-13-6-0-5-cb61094";
          dbsync-pre-release = "input-output-hk-cardano-db-sync-13-6-0-5-cb61094";
          metadata-server-release = "input-output-hk-offchain-metadata-tools-ops-1-0-0-f406c6d";
          mithril-release = "input-output-hk-mithril-2524-0-pre-7bf7033";
          mithril-pre-release = "input-output-hk-mithril-unstable-de4de82";
          node-release = "input-output-hk-cardano-node-10-5-1-ca1ec27";
          node-pre-release = "input-output-hk-cardano-node-10-5-1-ca1ec27";
        in
          submodule {
            options = foldl' recursiveUpdate {} [
              # TODO: Fix the missing meta/version info upstream
              (mkPkg "bech32" caPkgs."bech32-${node-release}")
              (mkPkg "blockfrost-platform" caPkgs.default-blockfrost-blockfrost-platform-0-0-2-e06029b)
              (mkPkg "blockperf" caPkgs.blockperf-cardano-foundation-blockperf-main-d757f38)
              (mkPkg "cardano-address" caPkgs."\"cardano-addresses:exe:cardano-address\"-IntersectMBO-cardano-addresses-4-0-0-3749045")
              (mkPkg "cardano-cli" (caPkgs."cardano-cli-${node-release}" // {version = "10.11.0.0";}))
              (mkPkg "cardano-cli-ng" (caPkgs."cardano-cli-${node-pre-release}" // {version = "10.11.0.0";}))
              (mkPkg "cardano-db-sync" caPkgs."\"cardano-db-sync:exe:cardano-db-sync\"-${dbsync-release}")
              (mkPkg "cardano-db-sync-ng" caPkgs."\"cardano-db-sync:exe:cardano-db-sync\"-${dbsync-pre-release}")
              (mkPkg "cardano-db-tool" caPkgs."\"cardano-db-tool:exe:cardano-db-tool\"-${dbsync-release}")
              (mkPkg "cardano-db-tool-ng" caPkgs."\"cardano-db-tool:exe:cardano-db-tool\"-${dbsync-pre-release}")

              # For tmp local faucet testing:
              # (mkPkg "cardano-faucet" localFlake.inputs.cardano-faucet.packages.x86_64-linux."cardano-faucet:exe:cardano-faucet")
              # (mkPkg "cardano-faucet-ng" localFlake.inputs.cardano-faucet.packages.x86_64-linux."cardano-faucet:exe:cardano-faucet")
              (mkPkg "cardano-faucet" caPkgs."\"cardano-faucet:exe:cardano-faucet\"-input-output-hk-cardano-faucet-10-1-2cccf6d")
              (mkPkg "cardano-faucet-ng" caPkgs."\"cardano-faucet:exe:cardano-faucet\"-input-output-hk-cardano-faucet-10-1-2cccf6d")

              (mkPkg "cardano-node" (caPkgs."cardano-node-${node-release}" // {version = "10.5.1";}))
              (mkPkg "cardano-node-ng" (caPkgs."cardano-node-${node-pre-release}" // {version = "10.5.1";}))
              (mkPkg "cardano-ogmios" caPkgs.ogmios-input-output-hk-cardano-ogmios-v6-11-2-df5971a)
              (mkPkg "cardano-signer" caPkgs.cardano-signer-johnalotoski-cardano-signer-v1-29-0-2ef95e1)
              (mkPkg "cardano-smash" caPkgs."cardano-smash-server-no-basic-auth-${dbsync-release}")
              (mkPkg "cardano-smash-ng" caPkgs."cardano-smash-server-no-basic-auth-${dbsync-pre-release}")
              (mkPkg "cardano-submit-api" caPkgs."cardano-submit-api-${node-release}")
              (mkPkg "cardano-submit-api-ng" caPkgs."cardano-submit-api-${node-pre-release}")
              (mkPkg "cardano-testnet" caPkgs."cardano-testnet-${node-release}")
              (mkPkg "cardano-testnet-ng" caPkgs."cardano-testnet-${node-pre-release}")
              (mkPkg "cardano-tracer" caPkgs."cardano-tracer-${node-release}")
              (mkPkg "cardano-tracer-ng" caPkgs."cardano-tracer-${node-pre-release}")
              (mkPkg "cardano-wallet" (caPkgs.cardano-wallet-cardano-foundation-cardano-wallet-v2025-03-31-1649791
                // {
                  pname = "cardano-wallet";
                  meta.description = "HTTP server and command-line for managing UTxOs and HD wallets in Cardano.";
                }))
              (mkPkg "cc-sign" caPkgs."cc-sign-${credential-manager-release}")
              (mkPkg "colmena" localFlake.inputs.colmena.packages.${system}.colmena)
              (mkPkg "db-analyser" caPkgs."db-analyser-${node-release}")
              (mkPkg "db-analyser-ng" caPkgs."db-analyser-${node-pre-release}")
              (mkPkg "db-synthesizer" caPkgs."db-synthesizer-${node-release}")
              (mkPkg "db-synthesizer-ng" caPkgs."db-synthesizer-${node-pre-release}")
              (mkPkg "db-truncater" caPkgs."db-truncater-${node-release}")
              (mkPkg "db-truncater-ng" caPkgs."db-truncater-${node-pre-release}")
              (mkPkg "isd" caPkgs.isd-isd-project-isd-v0-5-1-51d52a2)
              (mkPkg "process-compose" caPkgs.process-compose-F1bonacc1-process-compose-v1-46-0-6a1799e)
              (mkPkg "metadata-server" caPkgs."metadata-server-${metadata-server-release}")
              (mkPkg "metadata-sync" caPkgs."metadata-sync-${metadata-server-release}")
              (mkPkg "metadata-validator-github" caPkgs."metadata-validator-github-${metadata-server-release}")
              (mkPkg "metadata-webhook" caPkgs."metadata-webhook-${metadata-server-release}")
              (mkPkg "mithril-client-cli" (recursiveUpdate caPkgs."mithril-client-cli-${mithril-release}" {meta.mainProgram = "mithril-client";}))
              (mkPkg "mithril-client-cli-ng" (recursiveUpdate caPkgs."mithril-client-cli-${mithril-pre-release}" {meta.mainProgram = "mithril-client";}))
              (mkPkg "mithril-signer" (recursiveUpdate caPkgs."mithril-signer-${mithril-release}" {meta.mainProgram = "mithril-signer";}))
              (mkPkg "mithril-signer-ng" (recursiveUpdate caPkgs."mithril-signer-${mithril-pre-release}" {meta.mainProgram = "mithril-signer";}))
              (mkPkg "orchestrator-cli" caPkgs."orchestrator-cli-${credential-manager-release}")
              (mkPkg "snapshot-converter" caPkgs."snapshot-converter-${node-release}")
              (mkPkg "snapshot-converter-ng" caPkgs."snapshot-converter-${node-pre-release}")
              (mkPkg "token-metadata-creator" (recursiveUpdate caPkgs."token-metadata-creator-${metadata-server-release}" {meta.mainProgram = "token-metadata-creator";}))
              (mkPkg "tx-bundle" caPkgs."tx-bundle-${credential-manager-release}")
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
              blockfrost-platform
              blockperf
              cc-sign
              cardano-address
              cardano-cli
              cardano-db-sync
              cardano-db-tool
              cardano-faucet
              cardano-node
              cardano-ogmios
              cardano-signer
              cardano-smash
              cardano-submit-api
              cardano-testnet
              cardano-tracer
              cardano-wallet
              colmena
              db-analyser
              db-synthesizer
              db-truncater
              process-compose
              isd
              metadata-server
              metadata-sync
              metadata-validator-github
              metadata-webhook
              mithril-client-cli
              mithril-signer
              orchestrator-cli
              snapshot-converter
              token-metadata-creator
              tx-bundle
              ;

            # The `-ng` variants provide wrapped derivations to avoid cli collision with their non-wrapped, non-ng counterparts.
            cardano-cli-ng = mkWrapper "cardano-cli-ng" cfgPkgs.cardano-cli-ng;
            cardano-db-sync-ng = mkWrapper "cardano-db-sync-ng" cfgPkgs.cardano-db-sync-ng;
            cardano-db-tool-ng = mkWrapper "cardano-db-tool-ng" cfgPkgs.cardano-db-tool-ng;
            cardano-faucet-ng = mkWrapper "cardano-faucet-ng" cfgPkgs.cardano-faucet-ng;
            cardano-node-ng = mkWrapper "cardano-node-ng" cfgPkgs.cardano-node-ng;
            cardano-smash-ng = mkWrapper "cardano-smash-ng" cfgPkgs.cardano-smash-ng;
            cardano-submit-api-ng = mkWrapper "cardano-submit-api-ng" cfgPkgs.cardano-submit-api-ng;
            cardano-testnet-ng = mkWrapper "cardano-testnet-ng" cfgPkgs.cardano-testnet-ng;
            cardano-tracer-ng = mkWrapper "cardano-tracer-ng" cfgPkgs.cardano-tracer-ng;
            db-analyser-ng = mkWrapper "db-analyser-ng" cfgPkgs.db-analyser-ng;
            db-synthesizer-ng = mkWrapper "db-synthesizer-ng" cfgPkgs.db-synthesizer-ng;
            db-truncater-ng = mkWrapper "db-truncater-ng" cfgPkgs.db-truncater-ng;
            mithril-client-cli-ng = mkWrapper "mithril-client-ng" cfgPkgs.mithril-client-cli-ng;
            mithril-signer-ng = mkWrapper "mithril-signer-ng" cfgPkgs.mithril-signer-ng;
            snapshot-converter-ng = mkWrapper "snapshot-converter-ng" cfgPkgs.snapshot-converter-ng;
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
