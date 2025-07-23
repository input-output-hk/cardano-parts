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
      inherit (builtins) attrNames elem;
      inherit (lib) boolToString concatStringsSep escapeShellArgs getExe;
      inherit (opsLib) generateStaticHTMLConfigs mithrilAllowedAncillaryNetworks mithrilAllowedNetworks mithrilVerifyingPools;

      cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
      cardanoLibNg = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      cfgPkgs = config.cardano-parts.pkgs;

      # Copy the environment configs from iohk-nix into our jobs at runtime
      copyEnvsTemplate = cardanoLib: let
        inherit (cardanoLib) environments;

        envCfgs = generateStaticHTMLConfigs pkgs cardanoLib environments;

        isMithrilAncillary = env:
          boolToString (
            environments.${env} ? mithrilAggregatorEndpointUrl && elem env mithrilAllowedAncillaryNetworks
          );

        isMithrilEnv = env:
          boolToString (
            environments.${env} ? mithrilAggregatorEndpointUrl && elem env mithrilAllowedNetworks
          );
      in ''
        # Prepare standard env configs
        ENVS=(${escapeShellArgs (attrNames environments)})
        for ENV in "''${ENVS[@]}"; do
          cp -r "${envCfgs}/config/$ENV" "$DATA_DIR/config/"
        done

        # Until https://github.com/IntersectMBO/cardano-node/pull/6282 is merged and released,
        # remove PrometheusSimple from configs so multiple instances can be started without fatal error.
        find "$DATA_DIR/config" -type f -exec sed -i '/PrometheusSimple/d' {} +

        # Prepare mithril client env configs
        ${
          concatStringsSep "\n"
          (
            map (
              env:
                "declare -A MITHRIL_CFG_${env}\n"
                + "MITHRIL_CFG_${env}[MITHRIL_ENV]=\"${isMithrilEnv env}\"\n"
                + "MITHRIL_CFG_${env}[AGG_ENDPOINT]=\"${environments.${env}.mithrilAggregatorEndpointUrl or ""}\"\n"
                + "MITHRIL_CFG_${env}[GENESIS_VKEY]=\"${environments.${env}.mithrilGenesisVerificationKey or ""}\"\n"
                + "MITHRIL_CFG_${env}[ANCILLARY_ENV]=\"${isMithrilAncillary env}\"\n"
                + "MITHRIL_CFG_${env}[ANCILLARY_VKEY]=\"${environments.${env}.mithrilAncillaryVerificationKey or ""}\"\n"
                + "MITHRIL_CFG_${env}[VERIFYING_POOLS]=\"${concatStringsSep "|" (mithrilVerifyingPools.${env} or [])}\"\n"
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
          runtimeInputs = with pkgs; [curl gnugrep jq];

          # Since we don't know what chain network will be used at runtime, we populate
          # all the network mithril parameters at build time in copyEnvsTemplate.
          #
          # Since only one network will be used during runtime, this shellcheck
          # exclusion makes sure the script doesn't fail because of the presence
          # of other declared but unused mithril related env vars.
          excludeShellChecks = ["SC2034"];
          text = ''
            [ -n "''${DEBUG:-}" ] && set -x

            [ -z "''${DATA_DIR:-}" ] && echo "DATA_DIR env var must be set -- aborting" && exit 1

            mkdir -p "$DATA_DIR/config/custom"

            # The menu of environments that we ship as built-in envs
            if [ "''${UNSTABLE_LIB:-}" = "true" ]; then
              echo "Preparing environments using cardanoLibNg"
              ${copyEnvsTemplate cardanoLibNg}
            else
              echo "Preparing environments using cardanoLib"
              ${copyEnvsTemplate cardanoLib}
            fi

            chmod -R +w "$DATA_DIR/config" "$DATA_DIR/config/custom"

            if [ -n "''${ENVIRONMENT:-}" ]; then
              echo "Using the preset environment $ENVIRONMENT ..." >&2

              # Subst hyphen for underscore as iohk-nix envs historically use the former
              if [ "''${USE_NODE_CONFIG_BP:-}" = "true" ]; then
                NODE_CONFIG="$DATA_DIR/config/''${ENVIRONMENT/-/_}/config-bp.json"
              else
                NODE_CONFIG="$DATA_DIR/config/''${ENVIRONMENT/-/_}/config.json"
              fi
              NODE_TOPOLOGY="''${NODE_TOPOLOGY:-$DATA_DIR/config/''${ENVIRONMENT/-/_}/topology.json}"
            else
              [ -z "''${NODE_CONFIG:-}" ] && echo "NODE_CONFIG env var must be set for custom config -- aborting" && exit 1
              echo "Using custom config: $NODE_CONFIG ..." >&2
            fi

            DB_DIR="$DATA_DIR/db-''${ENVIRONMENT:-custom}"

            # The following environment variables may be used to modify default process compose mithril behavior:
            #   MITHRIL_DISABLE
            #   MITHRIL_DISABLE_ANCILLARY
            #   MITHRIL_SNAPSHOT_DIGEST
            #   MITHRIL_VERIFY_SNAPSHOT
            #   MITHRIL_VERIFYING_POOLS
            if [ -z "''${MITHRIL_DISABLE:-}" ] && [ "''${ENVIRONMENT:-custom}" != "custom" ]; then

              # Use an indirect reference to access the runtime environment associative mithril config array
              mithrilAttr() {
                declare -n POINTER="MITHRIL_CFG_''${1/-/_}"
                echo "''${POINTER[$2]}"
              }

              if [ "$(mithrilAttr "$ENVIRONMENT" "MITHRIL_ENV")" = "true" ]; then
                if [ "''${UNSTABLE_MITHRIL:-}" = "true" ]; then
                  MITHRIL_CLIENT="${config.cardano-parts.pkgs.mithril-client-cli-ng}/bin/mithril-client"
                else
                  MITHRIL_CLIENT="${config.cardano-parts.pkgs.mithril-client-cli}/bin/mithril-client"
                fi

                if ! [ -d "$DB_DIR/node" ]; then
                  MITHRIL_SNAPSHOT_DIGEST="''${MITHRIL_SNAPSHOT_DIGEST:-latest}"
                  DIGEST="$MITHRIL_SNAPSHOT_DIGEST"

                  AGGREGATOR_ENDPOINT="$(mithrilAttr "$ENVIRONMENT" "AGG_ENDPOINT")"
                  export AGGREGATOR_ENDPOINT

                  CONTINUE="true"
                  TMPSTATE="''${DB_DIR}/node-mithril"
                  rm -rf "$TMPSTATE"

                  if [ "''${MITHRIL_VERIFY_SNAPSHOT:-true}" = "true" ]; then
                    if [ "$DIGEST" = "latest" ]; then
                      # If digest is "latest" search through all available recent snaps for signing verification.
                      SNAPSHOTS_JSON=$("$MITHRIL_CLIENT" cardano-db snapshot list --json)
                      HASHES=$(jq -r '.[] | .certificate_hash' <<< "$SNAPSHOTS_JSON")
                    else
                      # Otherwise, only attempt the specifically declared snapshot digest
                      SNAPSHOTS_JSON=$("$MITHRIL_CLIENT" cardano-db snapshot show "$DIGEST" --json | jq -s)
                      HASHES=$(jq -r --arg DIGEST "$DIGEST" '.[] | select(.digest == $DIGEST) | .certificate_hash' <<< "$SNAPSHOTS_JSON")
                    fi

                    SNAPSHOTS_COUNT=$(jq '. | length' <<< "$SNAPSHOTS_JSON")
                    VERIFYING_POOLS="''${MITHRIL_VERIFYING_POOLS:-$(mithrilAttr "$ENVIRONMENT" "VERIFYING_POOLS")}"
                    VERIFIED_SIGNED="false"
                    IDX=0

                    while read -r HASH; do
                      ((IDX+=1))
                      RESPONSE=$(curl -s "$AGGREGATOR_ENDPOINT/certificate/$HASH")
                      SIGNERS=$(jq -r '.metadata.signers[] | .party_id' <<< "$RESPONSE")
                      if VERIFIED_BY=$(grep -E "$VERIFYING_POOLS" <<< "$SIGNERS"); then
                        VERIFIED_HASH="$HASH"
                        VERIFIED_DIGEST=$(jq -r '.protocol_message.message_parts.snapshot_digest' <<< "$RESPONSE")
                        VERIFIED_SEALED=$(jq -r '.metadata.sealed_at' <<< "$RESPONSE")
                        VERIFIED_SIGNED="true"
                        break
                      fi
                    done <<< "$HASHES"

                    if [ "$VERIFIED_SIGNED" = "true" ]; then
                      echo "The following mithril snapshot was signed by verifying pool(s):"
                      echo "Verified Digest: $VERIFIED_DIGEST"
                      echo "Verified Hash: $VERIFIED_HASH"
                      echo "Verified Sealed At: $VERIFIED_SEALED"
                      echo "Number of snapshots under review: $SNAPSHOTS_COUNT"
                      echo "Position index: $IDX"
                      echo "Verifying pools:"
                      echo "$VERIFIED_BY"
                      DIGEST="$VERIFIED_DIGEST"

                    else
                      echo "Of the $SNAPSHOTS_COUNT mithril snapshots examined, none were signed by any of the verifying pools:"
                      echo "$VERIFYING_POOLS" | tr '|' '\n'
                      echo "Mithril snapshot usage will be skipped."
                      CONTINUE="false"
                    fi
                  fi

                  if [ "$CONTINUE" = "true" ]; then
                    echo "Bootstrapping cardano-node state from mithril..."
                    echo "To disable mithril syncing, set MITHRIL_DISABLE env var"

                    if [ "$(mithrilAttr "$ENVIRONMENT" "ANCILLARY_ENV")" = "true" ] && [ -z "''${MITHRIL_DISABLE_ANCILLARY:-}" ]; then
                      ANCILLARY_ARGS=("--include-ancillary" "--ancillary-verification-key" "$(mithrilAttr "$ENVIRONMENT" "ANCILLARY_VKEY")")
                      echo "Bootstrapping using ancillary state..."
                      echo "To disable ancillary state, set MITHRIL_DISABLE_ANCILLARY env var"
                    else
                      echo "Bootstrapping without ancillary state..."
                    fi

                    "$MITHRIL_CLIENT" --version
                    "$MITHRIL_CLIENT" \
                      -vvv \
                      cardano-db \
                      download \
                      "$DIGEST" \
                      --download-dir "$TMPSTATE" \
                      --genesis-verification-key "$(mithrilAttr "$ENVIRONMENT" "GENESIS_VKEY")" \
                      ''${ANCILLARY_ARGS:+''${ANCILLARY_ARGS[@]}}
                    mv "$TMPSTATE/db" "$DB_DIR/node"
                    rm -rf "$TMPSTATE"
                    echo "Mithril bootstrap complete for $DB_DIR/node"
                  fi
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
