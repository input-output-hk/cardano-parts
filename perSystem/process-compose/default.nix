flake @ {inputs, ...}: {
  perSystem = {
    config,
    self',
    lib,
    pkgs,
    system,
    ...
  }: let
    inherit (builtins) attrNames elem fromJSON readFile toString;
    inherit (lib) boolToString concatStringsSep concatMapStringsSep foldl' mkForce optionalString recursiveUpdate replaceStrings;
    inherit (cardanoLib) environments;
    inherit (opsLib) generateStaticHTMLConfigs mithrilAllowedAncillaryNetworks mithrilAllowedNetworks mithrilVerifyingPools;

    cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
    cardanoLibNg = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

    environmentsNg = cardanoLibNg.environments;
    envCfgs = generateStaticHTMLConfigs pkgs cardanoLib environments;
    envCfgsNg = generateStaticHTMLConfigs pkgs cardanoLibNg environmentsNg;

    # Node and dbsync versioning for local development testing.
    envBinCfgs = {
      mainnet = {
        isCardanoLibNg = false;
        isDbsyncNg = false;
        isMithrilNg = false;
        isNodeNg = false;
        magic = getMagic "mainnet";
      };
      preprod = {
        isCardanoLibNg = false;
        isDbsyncNg = false;
        isMithrilNg = false;
        isNodeNg = false;
        magic = getMagic "preprod";
      };
      preview = {
        isCardanoLibNg = false;
        isDbsyncNg = false;
        isMithrilNg = false;
        isNodeNg = false;
        magic = getMagic "preview";
      };
    };

    envVer = env: binCfg:
      if envBinCfgs.${env}.${binCfg}
      then "-ng"
      else "";

    envCfgs' = env:
      if envBinCfgs.${env}.isCardanoLibNg
      then envCfgsNg
      else envCfgs;

    envs = env:
      if envBinCfgs.${env}.isCardanoLibNg
      then environmentsNg
      else environments;

    toHyphen = s: replaceStrings ["_"] ["-"] s;
    toUnderscore = s: replaceStrings ["-"] ["_"] s;

    getMagic = env: toString (fromJSON (readFile (envs env).${toUnderscore env}.nodeConfig.ByronGenesisFile)).protocolConsts.protocolMagic;

    # The common state dir will be generic and relative since
    # we may run this from any consuming repository stored at
    # any path.
    #
    # We may wish to align this better with Justfile's handling
    # of node state at ${XDG_DATA_HOME:=$HOME/.local/share}/$REPO
    # in the future
    stateDir = "./.run";
    testStateDir = "./.run-test";
    commonLogDir = "$TMPDIR/process-compose/";

    preHook = ''
      [ -n "''${DEBUG:-}" ] && set -x
      export TMPDIR="''${TMPDIR:=/tmp}"

      if ! [ -d "$TMPDIR" ]; then
        if ! mkdir -p "$TMPDIR" &> /dev/null; then
          echo "This process-compose stack requires that \$TMPDIR exists"
          echo "This environment currently has \$TMPDIR set to $TMPDIR which cannot be created by the current user"
          exit 1
        fi
      elif ! [ -w "$TMPDIR" ]; then
        echo "This process-compose stack requires that \$TMPDIR is writable by the current user"
        echo "This environment currently has \$TMPDIR set to $TMPDIR which is not writable by the current user"
        exit 1
      fi
    '';

    mithril-client-bootstrap' = env: stateDir': let
      inherit ((envs env).${toUnderscore env}) mithrilAggregatorEndpointUrl mithrilAncillaryVerificationKey mithrilGenesisVerificationKey;

      isMithrilAncillary =
        (envs env).${toUnderscore env}
        ? mithrilAggregatorEndpointUrl
        && elem env mithrilAllowedAncillaryNetworks;

      isMithrilEnv =
        (envs env).${toUnderscore env}
        ? mithrilAggregatorEndpointUrl
        && elem env mithrilAllowedNetworks;
    in
      optionalString isMithrilEnv ''
        # The following environment variables may be used to modify default process compose mithril behavior:
        #   MITHRIL_DISABLE
        #   MITHRIL_DISABLE_ANCILLARY
        #   MITHRIL_DISABLE_ANCILLARY_${env}
        #   MITHRIL_DISABLE_${env}
        #   MITHRIL_SNAPSHOT_DIGEST_${env}
        #   MITHRIL_VERIFY_SNAPSHOT_${env}
        #   MITHRIL_VERIFYING_POOLS_${env}
        [ -n "''${DEBUG:-}" ] && set -x

        if [ -z "''${MITHRIL_DISABLE:-}" ] && [ -z "''${MITHRIL_DISABLE_${env}:-}" ]; then
          MITHRIL_CLIENT="${config.cardano-parts.pkgs."mithril-client-cli${envVer env "isMithrilNg"}"}/bin/mithril-client"
          DB_DIR="${stateDir'}/${env}/cardano-node/db"
          if ! [ -d "$DB_DIR" ]; then
            MITHRIL_SNAPSHOT_DIGEST_${env}="''${MITHRIL_SNAPSHOT_DIGEST_${env}:-latest}"
            DIGEST="$MITHRIL_SNAPSHOT_DIGEST_${env}"

            AGGREGATOR_ENDPOINT="${mithrilAggregatorEndpointUrl}"
            export AGGREGATOR_ENDPOINT

            CONTINUE="true"
            TMPSTATE="''${DB_DIR}-mithril"
            rm -rf "$TMPSTATE"

            if [ "''${MITHRIL_VERIFY_SNAPSHOT_${env}:-true}" = "true" ]; then
              if [ "$DIGEST" = "latest" ]; then
                # If digest is "latest" search through all available recent snaps for signing verification.
                SNAPSHOTS_JSON=$("$MITHRIL_CLIENT" cardano-db snapshot list --json)
                HASHES=$(jq -r '.[] | "\(.certificate_hash) \(.hash)"' <<< "$SNAPSHOTS_JSON")
              else
                # Otherwise, only attempt the specifically declared snapshot digest
                SNAPSHOTS_JSON=$("$MITHRIL_CLIENT" cardano-db snapshot show "$DIGEST" --json | jq -s)
                HASHES=$(jq -r --arg DIGEST "$DIGEST" '.[] | select(.digest == $DIGEST) | "\(.certificate_hash) \(.hash)"' <<< "$SNAPSHOTS_JSON")
              fi

              SNAPSHOTS_COUNT=$(jq '. | length' <<< "$SNAPSHOTS_JSON")
              VERIFYING_POOLS="''${MITHRIL_VERIFYING_POOLS_${env}:-${concatStringsSep "|" mithrilVerifyingPools.${env}}}"
              VERIFIED_SIGNED="false"
              IDX=0

              while read -r CERT_HASH DIGEST; do
                ((IDX+=1))
                RESPONSE=$(curl -s "$AGGREGATOR_ENDPOINT/certificate/$CERT_HASH")
                SIGNERS=$(jq -r '.metadata.signers[] | .party_id' <<< "$RESPONSE")
                if VERIFIED_BY=$(grep -E "$VERIFYING_POOLS" <<< "$SIGNERS"); then
                  VERIFIED_HASH="$CERT_HASH"
                  VERIFIED_DIGEST="$DIGEST"
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
              echo "To disable mithril syncing, set MITHRIL_DISABLE or MITHRIL_DISABLE_${env} env vars"

              # shellcheck disable=SC2050
              if [ "${boolToString isMithrilAncillary}" = "true" ] && [ -z "''${MITHRIL_DISABLE_ANCILLARY:-}" ] && [ -z "''${MITHRIL_DISABLE_ANCILLARY_${env}:-}" ]; then
                ANCILLARY_ARGS=("--include-ancillary" "--ancillary-verification-key" "${mithrilAncillaryVerificationKey}")
                echo "Bootstrapping using ancillary state..."
                echo "To disable ancillary state, set MITHRIL_DISABLE_ANCILLARY or MITHRIL_DISABLE_ANCILLARY_${env} env vars"
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
                --genesis-verification-key "${mithrilGenesisVerificationKey}" \
                ''${ANCILLARY_ARGS:+''${ANCILLARY_ARGS[@]}}
              mv "$TMPSTATE/db" "$DB_DIR"
              rm -rf "$TMPSTATE"
              echo "Mithril bootstrap complete for $DB_DIR"
            fi
          fi
        fi
      '';

    mkNodeProcess = env: namespace: stateDir': {
      inherit namespace;
      log_location = "${stateDir'}/${env}/cardano-node/node.log";
      command = pkgs.writeShellApplication {
        name = "cardano-node-${env}${envVer env "isNodeNg"}";
        runtimeInputs = with pkgs; [curl gnugrep jq];
        text = ''
          # Mithril bootstrap code will follow if the environment supports mithril.
          # This can be disabled set setting either MITHRIL_DISABLE or MITHRIL_DISABLE_${env} env vars.
          ${mithril-client-bootstrap' env stateDir'}

          ${config.cardano-parts.pkgs."cardano-node${envVer env "isNodeNg"}"}/bin/cardano-node run +RTS -N -RTS \
          --topology ${envCfgs' env}/config/${toUnderscore env}/topology.json \
          --database-path ${stateDir'}/${env}/cardano-node/db \
          --socket-path ${stateDir'}/${env}/cardano-node/node.socket \
          --config ${envCfgs' env}/config/${toUnderscore env}/config.json
        '';
      };
    };

    mkCliProcess = env: namespace: stateDir': {
      inherit namespace;
      log_location = "${stateDir'}/${env}/cardano-node/cli.log";
      command = pkgs.writeShellApplication {
        name = "cardano-node-${env}${envVer env "isNodeNg"}-query";
        text = ''
          CLI="${config.cardano-parts.pkgs."cardano-cli${envVer env "isNodeNg"}"}/bin/cardano-cli"
          SOCKET="${stateDir'}/${env}/cardano-node/node.socket"

          while ! [ -S "$SOCKET" ]; do
            echo "$(date -u --rfc-3339=seconds): Waiting 5 seconds for a node socket at $SOCKET"
            sleep 5
          done

          while ! "$CLI" query tip --socket-path "$SOCKET" --testnet-magic "${envBinCfgs.${env}.magic}" &> /dev/null; do
            echo "$(date -u --rfc-3339=seconds): Waiting 5 seconds for the socket to become active at $SOCKET"
            sleep 5
          done

          while true; do
            date -u --rfc-3339=seconds
            "$CLI" latest query tip
            echo
            sleep 10
          done
        '';
      };
      environment = {
        CARDANO_NODE_NETWORK_ID = envBinCfgs.${env}.magic;
        CARDANO_NODE_SOCKET_PATH = "${stateDir'}/${env}/cardano-node/node.socket";
      };
    };

    mkNodeStack' = {
      envList ? attrNames envBinCfgs,
      startDisabled ? true,
      stateDir' ? stateDir,
    }: {
      imports = [
        inputs.services-flake.processComposeModules.default
      ];

      cli = {
        inherit preHook;
        environment = {
          PC_NO_SERVER = true;
        };
      };
      package = self'.packages.process-compose;

      settings = {
        disable_env_expansion = false;
        log_location = "${commonLogDir}/node-stack.log";
        processes =
          foldl' (acc: env:
            recursiveUpdate acc
            {
              "cardano-node-${env}${envVer env "isNodeNg"}" = mkNodeProcess env env stateDir' // {disabled = startDisabled;};
              "cardano-node-${env}${envVer env "isNodeNg"}-query" = mkCliProcess env env stateDir' // {disabled = startDisabled;};
            }) {}
          envList
          // {
            access-instructions = {
              command = pkgs.writeShellApplication {
                name = "access-instructions";
                text = ''
                  echo "This process-compose stack presents cardano-node jobs for each testnet chain and mainnet."
                  echo "Any or all of these jobs may be started (and stopped) with the control keys shown at the bottom of the TUI."
                  echo "The \".*-query\" jobs provide an ongoing sync status for each respective environment."
                  echo
                  echo "The cardano-cli or cardano-cli-ng commands from the cardano-parts \"ops\" devShell can be"
                  echo "can be used to connect to each environment."
                  echo
                  echo "If you don't have an \"ops\" devShell handy, you can enter one with:"
                  echo
                  echo "  nix develop github:input-output-hk/cardano-parts#devShells.x86_64-linux.ops"
                  echo
                  echo "If an environment supports Mithril, it will be used to sync client state."
                  echo "Mithril syncing can be disabled by setting either of MITHRIL_DISABLE or MITHRIL_DISABLE_\$ENV env vars."
                  echo
                  echo "Connection parameters for each environment are:"
                  echo
                  ${concatMapStringsSep "\n"
                    (env: ''
                      echo "${env}:"
                      echo "  export CARDANO_NODE_SOCKET_PATH=${stateDir'}/${env}/cardano-node/node.socket"
                      echo "  export CARDANO_NODE_NETWORK_ID=${envBinCfgs.${env}.magic}"
                      echo
                    '')
                    envList}
                  echo
                  echo "^^^ Scroll to the top of this window to read all the instructions"

                  # Keep the TUI alive
                  while true; do
                    sleep 60;
                  done
                '';
              };
            };
          };
      };
    };

    # Default node stack with all environments
    mkNodeStack = mkNodeStack' {};

    mkDbsyncStack = env: let
      # To accomodate legacy shelley_qa env naming in iohk-nix, and any other env names introduced with `_` in the future
      env' = toHyphen env;

      # $TMPDIR needs to be exported in the preHook, otherwise the
      # dbsync readiness check won't evaluate properly
      socketDir = "$TMPDIR/process-compose/${env'}";
    in {
      imports = [
        inputs.services-flake.processComposeModules.default
      ];

      cli = {
        inherit preHook;
        environment = {
          PC_NO_SERVER = true;
        };
      };
      package = self'.packages.process-compose;

      services.postgres."postgres-${env'}" = {
        inherit socketDir;
        enable = true;
        dataDir = "${stateDir}/${env'}/cardano-db-sync/database";
        initialDatabases = [{name = "cexplorer";}];
        initialScript.after = ''
          CREATE USER cexplorer;
          ALTER DATABASE cexplorer OWNER TO cexplorer;
        '';
      };

      settings = {
        disable_env_expansion = false;
        log_location = "${commonLogDir}/${env'}/dbsync-${env'}.log";
        processes = {
          access-instructions = {
            command = pkgs.writeShellApplication {
              name = "access-instructions-${env'}${envVer env' "isDbsyncNg"}";
              text = ''
                echo "The dbsync cexplorer database for ${env'} environment may be accessed with:"
                echo
                echo "  ${pkgs.postgresql}/bin/psql -h ${socketDir} -U cexplorer -d cexplorer"
                echo
                echo "...or, if psql is already in your devShell path, then simply:"
                echo
                echo "  psql -h ${socketDir} -U cexplorer -d cexplorer"
                echo
                echo "If superuser postgres access is required, then use the \$USER this job was started with:"
                echo
                echo "  psql -h ${socketDir} -U $USER -d postgres"
              '';
            };
            depends_on."postgres-${env'}".condition = "process_healthy";
          };

          "postgres-${env'}" = {
            namespace = mkForce "postgresql";
            log_location = "${stateDir}/${env'}/cardano-db-sync/postgres.log";
          };

          "postgres-${env'}-init" = {
            namespace = mkForce "postgresql";
            log_location = "${stateDir}/${env'}/cardano-db-sync/postgres-init.log";
          };

          "cardano-node-${env'}${envVer env' "isNodeNg"}" = mkNodeProcess env' "cardano-node" stateDir;

          "cardano-node-${env'}${envVer env' "isNodeNg"}-query" = mkCliProcess env' "cardano-node" stateDir;

          "cardano-db-sync-${env'}${envVer env' "isDbsyncNg"}" = {
            namespace = "cardano-db-sync";
            log_location = "${stateDir}/${env'}/cardano-db-sync/dbsync.log";
            command = pkgs.writeShellApplication {
              name = "cardano-db-sync-${env'}${envVer env' "isDbsyncNg"}";
              runtimeInputs = [pkgs.postgresql];
              text = ''
                # Export PGPASSFILE here rather than set a process-compose environment var
                # so that we can substitute runtime env vars which socketDir may use, ex: $TMPDIR
                export PGPASSFILE="${stateDir}/${env'}/cardano-db-sync/pgpass"
                echo "${socketDir}:5432:cexplorer:cexplorer:*" > "$PGPASSFILE"
                chmod 0600 "$PGPASSFILE"

                ${config.cardano-parts.pkgs."cardano-db-sync${envVer env' "isDbsyncNg"}"}/bin/cardano-db-sync \
                  --config ${envCfgs' env'}/config/${env}/db-sync-config.json \
                  --socket-path ${stateDir}/${env'}/cardano-node/node.socket \
                  --state-dir ${stateDir}/${env'}/cardano-db-sync/ledger-state \
                  --schema-dir ${flake.config.flake.cardano-parts.pkgs.special."cardano-db-sync-schema${envVer env' "isDbsyncNg"}"}
              '';
            };
            depends_on."postgres-${env'}".condition = "process_healthy";
          };
        };
      };
    };

    ## Process-Compose CI Test Stacks
    ## These stacks test that process-compose correctly orchestrates Cardano services.

    # Test process that validates cardano-node started and accepts CLI queries
    mkTestNodeProcess' = {
      env,
      maxRetries ? 60,
    }: {
      command = pkgs.writeShellApplication {
        name = "test-node-startup-${env}";
        runtimeInputs = with pkgs; [coreutils];
        text = ''
          CLI="${config.cardano-parts.pkgs."cardano-cli${envVer env "isNodeNg"}"}/bin/cardano-cli"
          SOCKET="${stateDir}/${env}/cardano-node/node.socket"
          MAX_RETRIES=${toString maxRetries}
          RETRY_DELAY=5

          echo "Starting cardano-node startup test for ${env}..."
          echo "Will wait up to $((MAX_RETRIES * RETRY_DELAY)) seconds for node to be ready"

          # Phase 1: Wait for socket file to exist
          echo "Phase 1: Waiting for socket file..."
          RETRIES=0
          while ! [ -S "$SOCKET" ]; do
            RETRIES=$((RETRIES + 1))
            if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
              echo "FAILED: Socket file did not appear after $((MAX_RETRIES * RETRY_DELAY)) seconds"
              exit 1
            fi
            echo "  Attempt $RETRIES/$MAX_RETRIES: Socket not found, waiting $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
          done
          echo "  Socket file found at $SOCKET"

          # Phase 2: Wait for socket to accept queries
          echo "Phase 2: Waiting for node to accept CLI queries..."
          RETRIES=0
          while ! "$CLI" query tip --socket-path "$SOCKET" --testnet-magic "${envBinCfgs.${env}.magic}" &> /dev/null; do
            RETRIES=$((RETRIES + 1))
            if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
              echo "FAILED: Node did not respond to queries after $((MAX_RETRIES * RETRY_DELAY)) seconds"
              exit 1
            fi
            echo "  Attempt $RETRIES/$MAX_RETRIES: Node not ready, waiting $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
          done

          # Phase 3: Get and display tip info
          echo "Phase 3: Querying node tip..."
          TIP=$("$CLI" query tip --socket-path "$SOCKET" --testnet-magic "${envBinCfgs.${env}.magic}")
          echo "Node tip:"
          while IFS= read -r line; do echo "  $line"; done <<< "$TIP"

          echo ""
          echo "========================================="
          echo "SUCCESS: cardano-node startup test PASSED"
          echo "========================================="
        '';
      };
      availability = {
        exit_on_end = true;
      };
      depends_on."cardano-node-${env}${envVer env "isNodeNg"}".condition = "process_started";
    };

    # Default wrapper with standard timeout
    mkTestNodeProcess = env: mkTestNodeProcess' {inherit env;};

    # Test process that validates db-sync connected and is syncing
    mkTestDbsyncProcess = env: socketDir: {
      command = pkgs.writeShellApplication {
        name = "test-dbsync-startup-${env}";
        runtimeInputs = with pkgs; [coreutils postgresql];
        text = ''
          CLI="${config.cardano-parts.pkgs."cardano-cli${envVer env "isNodeNg"}"}/bin/cardano-cli"
          NODE_SOCKET="${stateDir}/${env}/cardano-node/node.socket"
          PG_SOCKET="${socketDir}"
          MAX_RETRIES=60
          RETRY_DELAY=5

          echo "Starting db-sync integration test for ${env}..."

          # Phase 1: Wait for cardano-node to be ready
          echo "Phase 1: Waiting for cardano-node..."
          RETRIES=0
          while ! "$CLI" query tip --socket-path "$NODE_SOCKET" --testnet-magic "${envBinCfgs.${env}.magic}" &> /dev/null; do
            RETRIES=$((RETRIES + 1))
            if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
              echo "FAILED: cardano-node did not respond after $((MAX_RETRIES * RETRY_DELAY)) seconds"
              exit 1
            fi
            echo "  Attempt $RETRIES/$MAX_RETRIES: Node not ready, waiting $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
          done
          echo "  cardano-node is ready"

          # Phase 2: Wait for PostgreSQL and db-sync to have the schema ready
          echo "Phase 2: Waiting for db-sync schema..."
          RETRIES=0
          while ! psql -h "$PG_SOCKET" -U cexplorer -d cexplorer -c "SELECT 1 FROM block LIMIT 1;" &> /dev/null; do
            RETRIES=$((RETRIES + 1))
            if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
              echo "FAILED: db-sync schema not ready after $((MAX_RETRIES * RETRY_DELAY)) seconds"
              exit 1
            fi
            echo "  Attempt $RETRIES/$MAX_RETRIES: Schema not ready, waiting $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
          done
          echo "  db-sync schema is ready"

          # Phase 3: Verify db-sync is actually inserting blocks
          echo "Phase 3: Checking for block data..."
          BLOCK_COUNT=$(psql -h "$PG_SOCKET" -U cexplorer -d cexplorer -t -c "SELECT COUNT(*) FROM block;" | tr -d ' ')
          echo "  Current block count: $BLOCK_COUNT"

          # Wait a bit and check if count increases
          sleep 10
          NEW_BLOCK_COUNT=$(psql -h "$PG_SOCKET" -U cexplorer -d cexplorer -t -c "SELECT COUNT(*) FROM block;" | tr -d ' ')
          echo "  Block count after 10s: $NEW_BLOCK_COUNT"

          if [ "$NEW_BLOCK_COUNT" -gt "$BLOCK_COUNT" ]; then
            echo "  Blocks are being synced (increased by $((NEW_BLOCK_COUNT - BLOCK_COUNT)))"
          else
            echo "FAILED: Block count did not increase after 10 seconds"
            echo "  This may indicate db-sync is not syncing properly"
            exit 1
          fi

          echo ""
          echo "========================================="
          echo "SUCCESS: db-sync integration test PASSED"
          echo "========================================="
        '';
      };
      availability = {
        exit_on_end = true;
      };
      depends_on = {
        "postgres-${env}".condition = "process_healthy";
        "cardano-db-sync-${env}${envVer env "isDbsyncNg"}".condition = "process_started";
      };
    };

    # Node test stack - extends mkNodeStack' with test overrides
    mkNodeTestStack = env:
      recursiveUpdate (mkNodeStack' {
        envList = [env];
        startDisabled = false;
      }) {
        cli.environment.PC_DISABLE_TUI = true;
        settings.processes = {
          access-instructions.disabled = true;
          "cardano-node-${env}${envVer env "isNodeNg"}-query".disabled = true;
          "cardano-node-${env}${envVer env "isNodeNg"}" = {
            log_location = "";
            readiness_probe = {
              exec.command = "test -S ${stateDir}/${env}/cardano-node/node.socket";
              initial_delay_seconds = 10;
              period_seconds = 5;
              timeout_seconds = 5;
              failure_threshold = 60;
            };
            environment = {
              MITHRIL_DISABLE = "1";
            };
          };
          "test-node-startup" = mkTestNodeProcess env;
        };
      };

    # DB-sync test stack - extends mkDbsyncStack with test overrides
    mkDbsyncTestStack = env: let
      env' = toHyphen env;
      # Must match the socketDir used in mkDbsyncStack
      socketDir = "$TMPDIR/process-compose/${env'}";
    in
      recursiveUpdate (mkDbsyncStack env) {
        cli.environment.PC_DISABLE_TUI = true;
        settings.processes = {
          access-instructions.disabled = true;
          "cardano-node-${env'}${envVer env' "isNodeNg"}-query".disabled = true;
          "cardano-node-${env'}${envVer env' "isNodeNg"}" = {
            log_location = "";
            readiness_probe = {
              exec.command = "test -S ${stateDir}/${env'}/cardano-node/node.socket";
              initial_delay_seconds = 10;
              period_seconds = 5;
              timeout_seconds = 5;
              failure_threshold = 60;
            };
            environment = {
              MITHRIL_DISABLE = "1";
            };
          };
          "cardano-db-sync-${env'}${envVer env' "isDbsyncNg"}".log_location = "";
          "postgres-${env'}".log_location = "";
          "test-dbsync-startup" = mkTestDbsyncProcess env' socketDir;
        };
      };

    # Mithril download log patterns per network
    # These match the first GET request for snapshot immutable files, confirming download started
    mithrilLogPatterns = {
      mainnet = "DEBG GET Snapshot location='https://storage.googleapis.com/cdn.aggregator.release-mainnet.api.mithril.network/cardano-database/immutable";
      preprod = "DEBG GET Snapshot location='https://storage.googleapis.com/cdn.aggregator.release-preprod.api.mithril.network/cardano-database/immutable";
      preview = "DEBG GET Snapshot location='https://storage.googleapis.com/cdn.aggregator.pre-release-preview.api.mithril.network/cardano-database/immutable";
    };

    # Test process that exits successfully once Mithril download has started
    mkTestMithrilSuccess = env: {
      command = pkgs.writeShellApplication {
        name = "test-mithril-success-${env}";
        text = ''
          echo ""
          echo "========================================="
          echo "SUCCESS: Mithril download started for ${env}"
          echo "========================================="
        '';
      };
      availability = {
        exit_on_end = true;
      };
      # process_log_ready triggers when ready_log_line pattern is matched
      depends_on."cardano-node-${env}${envVer env "isNodeNg"}".condition = "process_log_ready";
    };

    # Node test stack with Mithril enabled - watches for download log line, then exits
    mkNodeMithrilTestStack = env:
      recursiveUpdate (mkNodeStack' {
        envList = [env];
        startDisabled = false;
        stateDir' = testStateDir;
      }) {
        cli.environment.PC_DISABLE_TUI = true;
        settings.processes = {
          access-instructions.disabled = true;
          "cardano-node-${env}${envVer env "isNodeNg"}-query".disabled = true;
          # Clean up any existing db so Mithril download is triggered
          "cleanup-db-${env}" = {
            command = pkgs.writeShellApplication {
              name = "cleanup-db-${env}";
              text = ''
                echo "Removing existing test db to force Mithril download..."
                rm -rf "${testStateDir}/${env}/cardano-node/db"
                echo "Cleanup complete"
              '';
            };
          };
          "cardano-node-${env}${envVer env "isNodeNg"}" = {
            ready_log_line = mithrilLogPatterns.${env};
            depends_on."cleanup-db-${env}".condition = "process_completed_successfully";
            environment."MITHRIL_VERIFY_SNAPSHOT_${env}" = "false";
          };
          "test-mithril-success" = mkTestMithrilSuccess env;
        };
      };
  in {
    process-compose = {
      run-process-compose-dbsync-mainnet = mkDbsyncStack "mainnet";
      run-process-compose-dbsync-preprod = mkDbsyncStack "preprod";
      run-process-compose-dbsync-preview = mkDbsyncStack "preview";
      run-process-compose-node-stack = mkNodeStack;

      test-process-compose-node-mainnet = mkNodeTestStack "mainnet";
      test-process-compose-node-preprod = mkNodeTestStack "preprod";
      test-process-compose-node-preview = mkNodeTestStack "preview";
      test-process-compose-dbsync-mainnet = mkDbsyncTestStack "mainnet";
      test-process-compose-dbsync-preprod = mkDbsyncTestStack "preprod";
      test-process-compose-dbsync-preview = mkDbsyncTestStack "preview";
      test-process-compose-node-mithril-mainnet = mkNodeMithrilTestStack "mainnet";
      test-process-compose-node-mithril-preprod = mkNodeMithrilTestStack "preprod";
      test-process-compose-node-mithril-preview = mkNodeMithrilTestStack "preview";
    };
  };
}
