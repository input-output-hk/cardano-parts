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
    inherit (builtins) fromJSON readFile;
    inherit (lib) mkForce replaceStrings;
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
      };
      preprod = {
        isNodeNg = false;
        isDbsyncNg = true;
      };
      preview = {
        isNodeNg = false;
        isDbsyncNg = true;
      };
      private = {
        isNodeNg = true;
        isDbsyncNg = true;
      };
      sanchonet = {
        isNodeNg = true;
        isDbsyncNg = true;
      };
      shelley-qa = {
        isNodeNg = true;
        isDbsyncNg = true;
      };
    };

    envVer = env: binCfg:
      if envBinCfgs.${env}.${binCfg}
      then "-ng"
      else "";

    mkDbsyncStack = env: let
      # To accomodate legacy shelley_qa env naming in iohk-nix
      env' = replaceStrings ["_"] ["-"] env;

      # The common state dir will be generic and relative since
      # we may run this from any consuming repository stored at
      # any path.
      #
      # We may wish to align this better with Justfile's handling
      # of node state at ${XDG_DATA_HOME:=$HOME/.local/share}/$REPO
      # in the future
      stateDir = "./.run";

      # It would be nice to set this to "${TMPDIR:=/tmp}/..."
      # but the process-compose bin doesn't currently allow for
      # shell interpolation in the probe commands
      socketDir = "/tmp/process-compose/${env'}";
      commonLogDir = "/tmp/process-compose/${env'}";
    in {
      imports = [
        inputs.services-flake.processComposeModules.default
      ];

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
        log_location = "${commonLogDir}/${env'}.log";
        processes = {
          "postgres-${env'}" = {
            namespace = mkForce "postgresql";
            log_location = "${stateDir}/${env'}/cardano-db-sync/postgres.log";
          };

          "postgres-${env'}-init" = {
            namespace = mkForce "postgresql";
            log_location = "${stateDir}/${env'}/cardano-db-sync/postgres-init.log";
          };

          "cardano-node-${env'}${envVer env' "isNodeNg"}" = {
            namespace = "cardano-node";
            log_location = "${stateDir}/${env'}/cardano-node/node.log";
            command = ''
              ${config.cardano-parts.pkgs."cardano-node${envVer env' "isNodeNg"}"}/bin/cardano-node run +RTS -N -RTS \
              --topology ${envCfgs}/config/${env}/topology.json \
              --database-path ${stateDir}/${env'}/cardano-node/db \
              --socket-path ${stateDir}/${env'}/cardano-node/node.socket \
              --config ${envCfgs}/config/${env}/config.json
            '';
          };

          "cardano-cli-${env'}${envVer env' "isNodeNg"}" = let
            testnetMagic = toString (fromJSON (readFile environments.${env}.nodeConfig.ByronGenesisFile)).protocolConsts.protocolMagic;
          in {
            namespace = "cardano-node";
            log_location = "${stateDir}/${env'}/cardano-node/cli.log";
            command = pkgs.writeShellApplication {
              name = "cardano-cli-${env'}${envVer env' "isNodeNg"}";
              text = ''
                CLI="${config.cardano-parts.pkgs."cardano-cli${envVer env' "isNodeNg"}"}/bin/cardano-cli"
                SOCKET="${stateDir}/${env'}/cardano-node/node.socket"

                while ! [ -S "$SOCKET" ]; do
                  echo "$(date -u --rfc-3339=seconds): Waiting 5 seconds for a node socket at $SOCKET"
                  sleep 5
                done

                while ! "$CLI" ping -c 1 -u "$SOCKET" -m "${testnetMagic}" &> /dev/null; do
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
              CARDANO_NODE_NETWORK_ID = testnetMagic;
              CARDANO_NODE_SOCKET_PATH = "${stateDir}/${env'}/cardano-node/node.socket";
            };
          };

          "cardano-db-sync-${env'}${envVer env' "isDbsyncNg"}" = {
            namespace = "cardano-db-sync";
            log_location = "${stateDir}/${env'}/cardano-db-sync/dbsync.log";
            command = pkgs.writeShellApplication {
              name = "cardano-db-sync-${env'}${envVer env' "isDbsyncNg"}";
              text = ''
                ${config.cardano-parts.pkgs."cardano-db-sync${envVer env' "isDbsyncNg"}"}/bin/cardano-db-sync \
                  --config ${envCfgs}/config/${env}/db-sync-config.json \
                  --socket-path ${stateDir}/${env'}/cardano-node/node.socket \
                  --state-dir ${stateDir}/${env'}/cardano-db-sync/ledger-state \
                  --schema-dir ${flake.config.flake.cardano-parts.pkgs.special."cardano-db-sync-schema${envVer env' "isDbsyncNg"}"}
              '';
            };
            environment.PGPASSFILE = "${pkgs.writeText "pgpass-${env'}" "${socketDir}:5432:cexplorer:cexplorer:*"}";
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
    };
  };
}
