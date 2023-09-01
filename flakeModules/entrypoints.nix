flake @ {
  flake-parts-lib,
  lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in
  with lib; {
    options = {
      perSystem = mkPerSystemOption ({
        config,
        pkgs,
        system,
        ...
      }: let
        inherit (flake.config.flake.legacyPackages.${system}) cardanoLib;

        cfgPkgs = config.cardano-parts.pkgs;

        # Use the iohk-nix mkConfigHtml attr and transform the output to what mdbook expects
        generateStaticHTMLConfigs = environments: let
          cardano-deployment = cardanoLib.mkConfigHtml environments;
        in
          pkgs.runCommand "cardano-html" {} ''
            mkdir "$out"
            cp "${cardano-deployment}/index.html" "$out/"
            cp "${cardano-deployment}/rest-config.json" "$out/"

            ENVS=(${pkgs.lib.escapeShellArgs (builtins.attrNames environments)})
            for ENV in "''${ENVS[@]}"; do
              # Migrate each env from a flat dir to an ENV subdir
              mkdir -p "$out/config/$ENV"
              for i in $(find ${cardano-deployment} -type f -name "$ENV-*" -printf "%f\n"); do
                cp -v "${cardano-deployment}/$i" "$out/config/$ENV/''${i#"$ENV-"}"
              done

              # Adjust genesis file and config refs
              sed -i "s|\"$ENV-|\"|g" "$out/config/$ENV/config.json"
              sed -i "s|\"$ENV-|\"|g" "$out/config/$ENV/db-sync-config.json"

              # Adjust index.html file refs
              sed -i "s|$ENV-|config/$ENV/|g" "$out/index.html"
            done
          '';

        # Copy the environment configs from iohk-nix into our jobs at runtime
        copyEnvsTemplate = environments: let
          envCfgs = generateStaticHTMLConfigs environments;
        in ''
          # DATA_DIR is a runtime entrypoint env var which will contain the cp target
          mkdir -p "$DATA_DIR/config"

          ENVS=(${pkgs.lib.escapeShellArgs (builtins.attrNames environments)})
          for ENV in "''${ENVS[@]}"; do
            cp -r "${envCfgs}/config/$ENV" "$DATA_DIR/config/"
          done
        '';

        node-snapshots = {
          # https://update-cardano-mainnet.iohk.io/cardano-node-state/index.html#
          mainnet = {
            base_url = "https://update-cardano-mainnet.iohk.io/cardano-node-state";
            file_name = "db-mainnet.tar.gz";
          };
        };
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
            text = ''
              [ -z "''${DATA_DIR:-}" ] && echo "DATA_DIR env var must be set -- aborting" && exit 1

              mkdir -p "$DATA_DIR"
              mkdir -p "$DATA_DIR/config"
              chmod -R +w "$DATA_DIR/config"
              mkdir -p "$DATA_DIR/config/custom"
              chmod -R +w "$DATA_DIR/config/custom"

              # The menu of environments that we ship as built-in envs
              ${copyEnvsTemplate cardanoLib.environments}

              # CASE: built-in environment
              if [ -n "''${ENVIRONMENT:-}" ]; then
                echo "Using the preset environment $ENVIRONMENT ..." >&2

                # Subst hypgen for underscore as iohk-nix envs historically use the former while cardano-world uses the later
                NODE_CONFIG="$DATA_DIR/config/''${ENVIRONMENT/-/_}/config.json"
                NODE_TOPOLOGY="''${NODE_TOPOLOGY:-$DATA_DIR/config/''${ENVIRONMENT/-/_}/topology.json}"
              else
                echo "Using custom config: $NODE_CONFIG ..." >&2

                [ -z "''${NODE_CONFIG:-}" ] && echo "NODE_CONFIG env var must be set -- aborting" && exit 1
              fi

              DB_DIR="$DATA_DIR/db-''${ENVIRONMENT:-custom}"
              function pull_snapshot {
                [ -z "''${SNAPSHOT_BASE_URL:-}" ] && echo "SNAPSHOT_BASE_URL env var must be set -- aborting" && exit 1
                [ -z "''${SNAPSHOT_FILE_NAME:-}" ] && echo "SNAPSHOT_FILE_NAME env var must be set -- aborting" && exit 1
                [ -z "''${DATA_DIR:-}" ] && echo "DATA_DIR env var must be set -- aborting" && exit 1

                SNAPSHOT_DIR="$DATA_DIR/initial-snapshot"
                mkdir -p "$SNAPSHOT_DIR"

                # We are already initialized
                [ -s "$SNAPSHOT_DIR/$SNAPSHOT_FILE_NAME.sha256sum" ] && INITIALIZED="true" && return

                # shellcheck source=/dev/null
                source ${pkgs.cacert}/nix-support/setup-hook
                echo "Downloading $SNAPSHOT_BASE_URL/$SNAPSHOT_FILE_NAME into $SNAPSHOT_DIR ..." >&2
                if curl -fL "$SNAPSHOT_BASE_URL/$SNAPSHOT_FILE_NAME" --output "$SNAPSHOT_DIR/$SNAPSHOT_FILE_NAME"; then
                  echo "Downloading $SNAPSHOT_BASE_URL/$SNAPSHOT_FILE_NAME.sha256sum into $SNAPSHOT_DIR ..." >&2
                  if curl -fL "$SNAPSHOT_BASE_URL/$SNAPSHOT_FILE_NAME.sha256sum" --output "$SNAPSHOT_DIR/$SNAPSHOT_FILE_NAME.sha256sum"; then
                    echo -n "pushd: " >&2
                    pushd "$SNAPSHOT_DIR" >&2
                    echo "Validating sha256sum for ./$SNAPSHOT_FILE_NAME." >&2
                    if sha256sum -c "$SNAPSHOT_FILE_NAME.sha256sum" >&2; then
                      echo "Downloading $SNAPSHOT_BASE_URL/$SNAPSHOT_FILE_NAME{,.sha256sum} into $SNAPSHOT_DIR complete." >&2
                    else
                      echo "Could retrieve snapshot, but could not validate its checksum -- aborting" && exit 1
                    fi
                    echo -n "popd: " >&2
                    popd >&2
                  else
                    echo "Could retrieve snapshot, but not its sha256 file -- aborting" && exit 1
                  fi
                else
                  echo "No snapshot pulled -- aborting" && exit 1
                fi
              }

              function extract_snapshot_tgz_to {
                local TARGETDIR="$1"
                local STRIP="''${2:-0}"
                mkdir -p "$TARGETDIR"

                [ -n "''${INITIALIZED:-}" ] && return

                echo "Extracting snapshot to $TARGETDIR ..." >&2
                if tar --strip-components="$STRIP" -C "$TARGETDIR" -zxf "$SNAPSHOT_DIR/$SNAPSHOT_FILE_NAME"; then
                  echo "Extracting snapshot to $TARGETDIR complete." >&2
                else
                  echo "Extracting snapshot to $TARGETDIR failed -- aborting" && exit 1
                fi
              }

              if [ -n "''${ENVIRONMENT:-}" ] && [ -n "''${USE_SNAPSHOT:-}" ]; then
                # We are using a standard environment that already has known snapshots
                SNAPSHOTS="${builtins.toFile "snapshots.json" (builtins.toJSON node-snapshots)}"
                SNAPSHOT_BASE_URL="$(jq -e -r --arg CARDENV "$ENVIRONMENT" '.[$CARDENV].base_url' < "$SNAPSHOTS")"
                SNAPSHOT_FILE_NAME="$(jq -e -r --arg CARDENV "$ENVIRONMENT" '.[$CARDENV].file_name' < "$SNAPSHOTS")"
              fi

              if [ -n "''${SNAPSHOT_BASE_URL:-}" ]; then
                pull_snapshot
                extract_snapshot_tgz_to "$DB_DIR/node" 1
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
              if [ "''${UNSTABLE:-}" = "true" ]; then
                echo "${lib.getExe cfgPkgs.cardano-node-ng} run ''${args[*]} ''${RTS_FLAGS:+''${RTS_FLAGS[*]}}"
                exec ${lib.getExe cfgPkgs.cardano-node-ng} run "''${args[@]}" ''${RTS_FLAGS:+''${RTS_FLAGS[@]}}
              else
                echo "${lib.getExe cfgPkgs.cardano-node} run ''${args[*]} ''${RTS_FLAGS:+''${RTS_FLAGS[*]}}"
                exec ${lib.getExe cfgPkgs.cardano-node} run "''${args[@]}" ''${RTS_FLAGS:+''${RTS_FLAGS[@]}}
              fi
            '';
          };
        };
      });
    };
  }
