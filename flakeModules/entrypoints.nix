flake @ {flake-parts-lib, ...}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      lib,
      pkgs,
      system,
      ...
    }: let
      inherit (builtins) attrNames;
      inherit (lib) boolToString concatStringsSep escapeShellArgs getExe;
      inherit (opsLib) generateStaticHTMLConfigs;

      cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
      cardanoLibNg = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      cfgPkgs = config.cardano-parts.pkgs;

      # Copy the environment configs from iohk-nix into our jobs at runtime
      copyEnvsTemplate = environments: let
        envCfgs = generateStaticHTMLConfigs pkgs cardanoLib environments;
      in ''
        # Prepare standard env configs
        ENVS=(${escapeShellArgs (attrNames environments)})
        for ENV in "''${ENVS[@]}"; do
          cp -r "${envCfgs}/config/$ENV" "$DATA_DIR/config/"
        done

        # Prepare mithril client env configs
        ${
          concatStringsSep "\n"
          (
            map (
              env:
                "declare -A MITHRIL_CFG_${env}\n"
                + "MITHRIL_CFG_${env}[MITHRIL_ENV]=\"${boolToString (environments.${env} ? mithrilAggregatorEndpointUrl && env != "mainnet")}\"\n"
                + "MITHRIL_CFG_${env}[AGG_ENDPOINT]=\"${environments.${env}.mithrilAggregatorEndpointUrl or ""}\"\n"
                + "MITHRIL_CFG_${env}[GENESIS_VKEY]=\"${environments.${env}.mithrilGenesisVerificationKey or ""}\"\n"
            )
            (attrNames environments)
          )
        }
      '';
    in {
      # perSystem level option definition
      # options.cardano-parts = mkOption {
      #   type = mainSubmodule;
      # };

      config = {
        # Make entrypoints
        packages.run-cardano-node = pkgs.writeShellApplication {
          name = "run-cardano-node";
          runtimeInputs = [pkgs.jq];
          excludeShellChecks = ["SC2034"];
          text = ''
            [ -z "''${DATA_DIR:-}" ] && echo "DATA_DIR env var must be set -- aborting" && exit 1

            mkdir -p "$DATA_DIR/config/custom"
            chmod -R +w "$DATA_DIR/config" "$DATA_DIR/config/custom"

            # The menu of environments that we ship as built-in envs
            if [ "''${UNSTABLE_LIB:-}" = "true" ]; then
              echo "Preparing environments using cardanoLibNg"
              ${copyEnvsTemplate cardanoLibNg.environments}
            else
              echo "Preparing environments using cardanoLib"
              ${copyEnvsTemplate cardanoLib.environments}
            fi

            if [ -n "''${ENVIRONMENT:-}" ]; then
              echo "Using the preset environment $ENVIRONMENT ..." >&2

              # Subst hyphen for underscore as iohk-nix envs historically use the former
              NODE_CONFIG="$DATA_DIR/config/''${ENVIRONMENT/-/_}/config.json"
              NODE_TOPOLOGY="''${NODE_TOPOLOGY:-$DATA_DIR/config/''${ENVIRONMENT/-/_}/topology.json}"
            else
              [ -z "''${NODE_CONFIG:-}" ] && echo "NODE_CONFIG env var must be set for custom config -- aborting" && exit 1
              echo "Using custom config: $NODE_CONFIG ..." >&2
            fi

            DB_DIR="$DATA_DIR/db-''${ENVIRONMENT:-custom}"
            if [ -z "''${MITHRIL_DISABLE:-}" ] && [ "''${ENVIRONMENT:-custom}" != "custom" ]; then

              # Use an indirect reference to access the runtime environment associative mithril config array
              mithrilAttr() {
                declare -n POINTER="MITHRIL_CFG_''${1/-/_}"
                echo "''${POINTER[$2]}"
              }

              if [ "$(mithrilAttr "$ENVIRONMENT" "MITHRIL_ENV")" == "true" ]; then
                MITHRIL_CLIENT="${cfgPkgs.mithril-client-cli}/bin/mithril-client"
                TMPSTATE="''${DB_DIR}/node-mithril"
                rm -rf "$TMPSTATE"
                if ! [ -d "$DB_DIR/node" ]; then
                  echo "Bootstrapping cardano-node state from mithril"
                  echo "To disable mithril syncing, set MITHRIL_DISABLE env var"
                  "$MITHRIL_CLIENT" \
                    -vvv \
                    --aggregator-endpoint "$(mithrilAttr "$ENVIRONMENT" "AGG_ENDPOINT")" \
                    snapshot \
                    download \
                    "latest" \
                    --download-dir "$TMPSTATE" \
                    --genesis-verification-key "$(mithrilAttr "$ENVIRONMENT" "GENESIS_VKEY")"
                  mv "$TMPSTATE/db" "$DB_DIR/node"
                  rm -rf "$TMPSTATE"
                  echo "Mithril bootstrap complete for $DB_DIR/node"
                fi
              fi
            fi

            # Build args array
            args+=("--config" "$NODE_CONFIG")
            args+=("--database-path" "$DB_DIR/node")
            [ -n "''${HOST_ADDR:-}" ] && args+=("--host-addr" "$HOST_ADDR")
            [ -n "''${HOST_IPV6_ADDR:-}" ] && args+=("--host-ipv6-addr" "$HOST_IPV6_ADDR")
            [ -n "''${PORT:-}" ] && args+=("--port" "$PORT")
            [ -n "''${SOCKET_PATH:-}" ] && args+=("--socket-path" "$SOCKET_PATH")

            # If RTS flags are present, eval the RTS flag string for runtime dependency calcs,
            # and convert the output to an arg array for inclusion in node args if non-empty.
            if [ -n "''${RTS_FLAGS:-}" ]; then
              RTS_FLAGS=$(eval echo -n "$RTS_FLAGS")
              read -r -a RTS_FLAGS <<< "$RTS_FLAGS"
            fi

            [ -n "''${BYRON_DELEG_CERT:-}" ] && args+=("--byron-delegation-certificate" "$BYRON_DELEG_CERT")
            [ -n "''${BYRON_SIGNING_KEY:-}" ] && args+=("--byron-signing-key" "$BYRON_SIGNING_KEY")
            [ -n "''${SHELLEY_KES_KEY:-}" ] && args+=("--shelley-kes-key" "$SHELLEY_KES_KEY")
            [ -n "''${SHELLEY_VRF_KEY:-}" ] && args+=("--shelley-vrf-key" "$SHELLEY_VRF_KEY")
            [ -n "''${SHELLEY_OPCERT:-}" ] && args+=("--shelley-operational-certificate" "$SHELLEY_OPCERT")
            [ -n "''${BULK_CREDS:-}" ] && args+=("--bulk-credentials-file" "$BULK_CREDS")

            [ -z "''${NODE_TOPOLOGY:-}" ] && echo "NODE_TOPOLOGY env var must be set -- aborting" && exit 1
            args+=("--topology" "$NODE_TOPOLOGY")
            echo "Running node as:"
            if [ "''${USE_SHELL_BINS:-}" = "true" ]; then
              echo "cardano-node run ''${args[*]} ''${RTS_FLAGS:+''${RTS_FLAGS[*]}}"
              exec cardano-node run "''${args[@]}" ''${RTS_FLAGS:+''${RTS_FLAGS[@]}}
            elif [ "''${UNSTABLE:-}" = "true" ]; then
              echo "${getExe cfgPkgs.cardano-node-ng} run ''${args[*]} ''${RTS_FLAGS:+''${RTS_FLAGS[*]}}"
              exec ${getExe cfgPkgs.cardano-node-ng} run "''${args[@]}" ''${RTS_FLAGS:+''${RTS_FLAGS[@]}}
            else
              echo "${getExe cfgPkgs.cardano-node} run ''${args[*]} ''${RTS_FLAGS:+''${RTS_FLAGS[*]}}"
              exec ${getExe cfgPkgs.cardano-node} run "''${args[@]}" ''${RTS_FLAGS:+''${RTS_FLAGS[@]}}
            fi
          '';
        };
      };
    });
  };
}
