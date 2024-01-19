flake @ {
  # self,
  inputs,
  ...
}: {
  perSystem = {
    config,
    # inputs',
    self',
    lib,
    pkgs,
    system,
    ...
  }: let
    inherit (builtins) attrNames fromJSON readFile;
    inherit (lib) concatMapStringsSep foldl' mkForce recursiveUpdate replaceStrings;
    inherit (cardanoLib) environments;
    inherit (opsLib) generateStaticHTMLConfigs;

    cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLib system;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

    envCfgs = generateStaticHTMLConfigs pkgs cardanoLib environments;

    # Node and dbsync versioning for local development testing
    #
    # Note that mainnet, preprod, preview have dbsync set as `-ng` versioning
    # until the next release after 13.1.1.3 which will no longer require
    # the deprecated `ApplicationName` key to be set in the environment config
    envBinCfgs = {
      mainnet = {
        isNodeNg = false;
        isDbsyncNg = true;
        magic = getMagic "mainnet";
      };
      preprod = {
        isNodeNg = false;
        isDbsyncNg = true;
        magic = getMagic "preprod";
      };
      preview = {
        isNodeNg = false;
        isDbsyncNg = true;
        magic = getMagic "preview";
      };
      private = {
        isNodeNg = true;
        isDbsyncNg = true;
        magic = getMagic "private";
      };
      sanchonet = {
        isNodeNg = true;
        isDbsyncNg = true;
        magic = getMagic "sanchonet";
      };
      shelley-qa = {
        isNodeNg = true;
        isDbsyncNg = true;
        magic = getMagic "shelley-qa";
      };
    };

    envVer = env: binCfg:
      if envBinCfgs.${env}.${binCfg}
      then "-ng"
      else "";

    toHyphen = s: replaceStrings ["_"] ["-"] s;
    toUnderscore = s: replaceStrings ["-"] ["_"] s;

    getMagic = env: toString (fromJSON (readFile environments.${toUnderscore env}.nodeConfig.ByronGenesisFile)).protocolConsts.protocolMagic;

    # The common state dir will be generic and relative since
    # we may run this from any consuming repository stored at
    # any path.
    #
    # We may wish to align this better with Justfile's handling
    # of node state at ${XDG_DATA_HOME:=$HOME/.local/share}/$REPO
    # in the future
    stateDir = "./.run";
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

    mkNodeProcess = env: namespace: {
      inherit namespace;
      log_location = "${stateDir}/${env}/cardano-node/node.log";
      command = ''
        ${config.cardano-parts.pkgs."cardano-node${envVer env "isNodeNg"}"}/bin/cardano-node run +RTS -N -RTS \
        --topology ${envCfgs}/config/${toUnderscore env}/topology.json \
        --database-path ${stateDir}/${env}/cardano-node/db \
        --socket-path ${stateDir}/${env}/cardano-node/node.socket \
        --config ${envCfgs}/config/${toUnderscore env}/config.json
      '';
    };

    mkCliProcess = env: namespace: {
      inherit namespace;
      log_location = "${stateDir}/${env}/cardano-node/cli.log";
      command = pkgs.writeShellApplication {
        name = "cardano-node-${env}${envVer env "isNodeNg"}-query";
        text = ''
          CLI="${config.cardano-parts.pkgs."cardano-cli${envVer env "isNodeNg"}"}/bin/cardano-cli"
          SOCKET="${stateDir}/${env}/cardano-node/node.socket"

          while ! [ -S "$SOCKET" ]; do
            echo "$(date -u --rfc-3339=seconds): Waiting 5 seconds for a node socket at $SOCKET"
            sleep 5
          done

          while ! "$CLI" ping -c 1 -u "$SOCKET" -m "${envBinCfgs.${env}.magic}" &> /dev/null; do
            echo "$(date -u --rfc-3339=seconds): Waiting 5 seconds for the socket to become active at $SOCKET"
            sleep 5
          done

          while true; do
            date -u --rfc-3339=seconds
            "$CLI" query tip
            echo
            sleep 10
          done
        '';
      };
      environment = {
        CARDANO_NODE_NETWORK_ID = envBinCfgs.${env}.magic;
        CARDANO_NODE_SOCKET_PATH = "${stateDir}/${env}/cardano-node/node.socket";
      };
    };

    mkNodeStack = {
      imports = [
        inputs.services-flake.processComposeModules.default
      ];

      inherit preHook;

      apiServer = false;
      package = self'.packages.process-compose;
      tui = true;

      settings = {
        log_location = "${commonLogDir}/node-stack.log";
        processes =
          foldl' (acc: env:
            recursiveUpdate acc
            {
              "cardano-node-${env}${envVer env "isNodeNg"}" = mkNodeProcess env env // {disabled = true;};
              "cardano-node-${env}${envVer env "isNodeNg"}-query" = mkCliProcess env env // {disabled = true;};
            }) {} (attrNames envBinCfgs)
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
                  echo "Connection parameters for each environment are:"
                  echo
                  ${concatMapStringsSep "\n"
                    (env: ''
                      echo "${env}:"
                      echo "  export CARDANO_NODE_SOCKET_PATH=${stateDir}/${env}/cardano-node/node.socket"
                      echo "  export CARDANO_NODE_NETWORK_ID=${envBinCfgs.${env}.magic}"
                      echo
                    '') (attrNames envBinCfgs)}
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

    mkDbsyncStack = env: let
      # To accomodate legacy shelley_qa env naming in iohk-nix
      env' = toHyphen env;

      # $TMPDIR needs to be exported in the preHook, otherwise the
      # dbsync readiness check won't evaluate properly
      socketDir = "$TMPDIR/process-compose/${env'}";
    in {
      imports = [
        inputs.services-flake.processComposeModules.default
      ];

      inherit preHook;

      apiServer = false;
      package = self'.packages.process-compose;
      tui = true;

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

          "cardano-node-${env'}${envVer env' "isNodeNg"}" = mkNodeProcess env' "cardano-node";

          "cardano-node-${env'}${envVer env' "isNodeNg"}-query" = mkCliProcess env' "cardano-node";

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
                  --config ${envCfgs}/config/${env}/db-sync-config.json \
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
  in {
    process-compose = {
      run-process-compose-dbsync-mainnet = mkDbsyncStack "mainnet";
      run-process-compose-dbsync-preprod = mkDbsyncStack "preprod";
      run-process-compose-dbsync-preview = mkDbsyncStack "preview";
      run-process-compose-dbsync-private = mkDbsyncStack "private";
      run-process-compose-dbsync-sanchonet = mkDbsyncStack "sanchonet";
      run-process-compose-dbsync-shelley-qa = mkDbsyncStack "shelley_qa";
      run-process-compose-node-stack = mkNodeStack;
    };
  };
}
