# nixosModule: profile-cardano-db-sync-snapshots
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-db-sync-snapshots.bucket
#   config.services.cardano-db-sync-snapshots.blockDiffTolerance
#   config.services.cardano-db-sync-snapshots.environmentFile
#   config.services.cardano-db-sync-snapshots.group
#   config.services.cardano-db-sync-snapshots.prefix
#   config.services.cardano-db-sync-snapshots.user
#   config.services.cardano-db-sync-snapshots.useSopsSecrets
#
# Tips:
#   * This is a cardano-db-sync snapshots add-on to the cardano-parts profile-cardano-db-sync nixos service module
#   * This module provides cardano-db-sync snapshotting for push to an s3 distrubution bucket
#   * The cardano-parts profile-cardano-db-sync nixos service module should still be imported separately
flake: {
  flake.nixosModules.profile-cardano-db-sync-snapshots = {
    config,
    pkgs,
    lib,
    name,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) bool ints str;
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (perNodeCfg.meta) cardanoDbSyncPrometheusExporterPort;
      inherit (perNodeCfg.pkgs) cardano-cli;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) environmentName;
      inherit (cardanoLib.environments.${environmentName}.nodeConfig) ByronGenesisFile ShelleyGenesisFile;
      inherit ((fromJSON (readFile ByronGenesisFile)).protocolConsts) protocolMagic;
      inherit (fromJSON (readFile ShelleyGenesisFile)) systemStart epochLength;
      inherit (opsLib) mkSopsSecret;

      groupCfg = config.cardano-parts.cluster.group;
      groupOutPath = groupFlake.self.outPath;
      perNodeCfg = config.cardano-parts.perNode;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      mkSopsSecretParams = secretName: keyName: {
        inherit groupOutPath groupName name secretName keyName;
        fileOwner = cfg.user;
        fileGroup = cfg.group;
        restartUnits = ["cardano-db-sync-snapshots.service"];
      };

      cfg = config.services.cardano-db-sync-snapshots;
      cfgDbsync = config.services.cardano-db-sync;
      cfgNode = config.services.cardano-node;
    in {
      options = {
        services.cardano-db-sync-snapshots = {
          bucket = mkOption {
            type = str;
            default = null;
            example = "update-cardano-mainnet.iohk.io";
            description = "The bucket which the snapshots will be pushed to.";
          };

          blockDiffTolerance = mkOption {
            type = ints.positive;
            default = 180;
            description = "The maximum allowable number of blocks that cardano-db-sync may be behind cardano-node for a snapshot.";
          };

          environmentFile = mkOption {
            type = str;
            default =
              if cfg.useSopsSecrets
              then config.sops.secrets.cardano-db-sync-snapshots.path
              else null;
            description = ''
              The full path on the deployed machine filesystem to a systemd environmentFile which will contain the following keys and values:

                AWS_ACCESS_KEY_ID=********************
                AWS_SECRET_ACCESS_KEY=****************************************

              The credentials should allow minimum access to only the bucket and prefix to store snapshots.
              An example IAM policy would be the following where $BUCKET and $PREFIX are substituted:

                {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "",
                            "Effect": "Deny",
                            "Action": "s3:ListBucket",
                            "Resource": "arn:aws:s3:::$BUCKET",
                            "Condition": {
                                "StringNotLike": {
                                    "s3:prefix": [
                                        "$PREFIX*"
                                    ]
                                }
                            }
                        },
                        {
                            "Sid": "",
                            "Effect": "Allow",
                            "Action": [
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:PutObjectAcl"
                            ],
                            "Resource": "arn:aws:s3:::$BUCKET/$PREFIX/*"
                        }
                    ]
                }

              There will also be worth applied an auto-expire lifecycle so old snapshots don't accumulate.
              The `13.3` after the "Prefix" below is to apply the policy only to the snapshots in the current schema subdirectory
              and not to the main prefix directory, where schema 13.3 is the current schema at the time of this writing.
              The dbsync team may wish to keep at least one copy of old schema snapshots for testing which is why this lifecycle
              is only applied to the current schema subdirectory.

                $ aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --output json
                {
                    "Rules": [
                        {
                            "Expiration": {
                                "Days": 60
                            },
                            "ID": "Delete old 13.3 db-sync snapshots",
                            "Filter": {
                                "Prefix": "$PREFIX/13.3"
                            },
                            "Status": "Enabled"
                        }
                    ]
                }
            '';
          };

          group = mkOption {
            type = str;
            default = "root";
            description = ''
              The group of the cardano-db-sync-snapshots service.
              The group current defaults to root in order to conditionally restart cardano-db-sync from within itself.
            '';
          };

          prefix = mkOption {
            type = str;
            default = null;
            example = "cardano-db-sync";
            description = ''
              The prefix in the bucket which snapshots will be pushed to.

              The actual destination path for a snapshot will be:
                s3://''${cfg.bucket}/''${cfg.prefix}/$SCHEMA/"

              Where the $SCHEMA above is interpolated from the snapshot name.
            '';
          };

          user = mkOption {
            type = str;
            default = "root";
            description = ''
              The user of the cardano-db-sync-snapshots service.";
              The user current defaults to root in order to conditionally restart cardano-db-sync from within itself.
            '';
          };

          useSopsSecrets = mkOption {
            type = bool;
            default = true;
            description = ''
              Whether to use the default configurated sops secrets if true,
              or user defined secrets if false.

              If false, any required secrets will need to be provided either
              by additional module code or out of band.
            '';
          };
        };
      };

      config = {
        services = {
          cardano-db-sync = {
            takeSnapshot = "always";
          };
        };

        systemd = {
          services = {
            cardano-db-sync = {
              # Increase stop timeout to 12h, to allow for snapshot creation on mainnet.
              # Currently the snapshots take less than ~6h and 12h timeout will allow further db growth.
              serviceConfig.TimeoutStopSec = lib.mkForce "12h";
            };

            cardano-db-sync-snapshots = {
              wantedBy = ["multi-user.target"];

              environment = {
                CARDANO_NODE_NETWORK_ID = toString protocolMagic;
                CARDANO_NODE_SOCKET_PATH = cfgNode.socketPath 0;
              };

              serviceConfig = {
                Type = "oneshot";

                User = cfg.user;
                Group = cfg.group;

                EnvironmentFile = config.sops.secrets.cardano-db-sync-snapshots.path;

                ExecStart = getExe (pkgs.writeShellApplication {
                  name = "cardano-db-sync-snapshots";
                  runtimeInputs = with pkgs; [cardano-cli curl gawk jq ripgrep s3cmd systemd];

                  text = ''
                    echo "Starting cardano-db-sync-snapshots"
                    STATE_DIR=${cfgDbsync.stateDir}
                    cd "$STATE_DIR"

                    FAIL_FILE="$STATE_DIR/snapshot-update-failure"
                    RUNNING_FILE="$STATE_DIR/snapshot-update-in-progress"

                    # Guarantee that a snapshot attempt failure will result in a persistent systemd service failure,
                    # which will generate an on-going alert for manual intervention.
                    if [ -f "$FAIL_FILE" ]; then
                      echo "The cardano-db-sync-snapshots service has noticed a failure which should be investigated."
                      echo "Refusing to start until $FAIL_FILE file has been removed."
                      false
                    fi

                    PRE_EXIT() {
                      RC="$?"

                      # If exiting due to an error RC, set the fail file marker
                      if [ "$RC" != "0" ]; then
                        echo "The snapshots service failed with an RC of $RC, aborting with a failure status."
                        touch "$FAIL_FILE"
                      fi

                      exit "$RC"
                    }
                    trap 'PRE_EXIT' EXIT

                    SYSTEM_START="${systemStart}"
                    EPOCH_LENGTH_SEC="${toString epochLength}"

                    TS_DATE=$(date +%s)
                    TS_SYSTEM_START=$(date +%s -d "$SYSTEM_START")
                    CHAIN_RUNTIME_SEC=$((TS_DATE - TS_SYSTEM_START))
                    EPOCH_ELAPSED_SEC=$((CHAIN_RUNTIME_SEC % EPOCH_LENGTH_SEC))
                    EPOCH_REMAINING_SEC=$((EPOCH_LENGTH_SEC - EPOCH_ELAPSED_SEC))
                    HOURS_SINCE_LAST_EPOCH=$((EPOCH_ELAPSED_SEC / 3600))
                    HOURS_UNTIL_NEXT_EPOCH=$((EPOCH_REMAINING_SEC / 3600))

                    echo "Hours since last epoch are: $HOURS_SINCE_LAST_EPOCH"
                    echo "Hours until next epoch are: $HOURS_UNTIL_NEXT_EPOCH"

                    if [ "$HOURS_SINCE_LAST_EPOCH" -le "1" ]; then
                      echo "A new epoch has just started, attempting a snapshot and upload..."

                      if ! [ -f "$RUNNING_FILE" ]; then
                        # Ensure node is synced
                        NODE_SYNC_PERCENT=$(jq -re .syncProgress <<< "$(cardano-cli query tip)")
                        if [ "$NODE_SYNC_PERCENT" != "100.00" ]; then
                          echo "Cardano-node is not 100.00% synchronized, syncProgress is reported as \"$NODE_SYNC_PERCENT\"%, aborting with a failure status."
                          exit 1
                        fi
                        echo "Cardano-node is synchronized, syncProgress is reported as \"$NODE_SYNC_PERCENT\"%"

                        # Ensure cardano-db-sync is near tip of node and within tolerance
                        DBSYNC_METRICS=$(curl --fail --silent 127.0.0.1:${toString cardanoDbSyncPrometheusExporterPort})

                        NODE_BLOCK_HEIGHT=$(rg --only-matching '^cardano_db_sync_node_block_height[ ]+([0-9.e]+)' --replace '$1' <<< "$DBSYNC_METRICS")
                        DBSYNC_BLOCK_HEIGHT=$(rg --only-matching '^cardano_db_sync_db_block_height[ ]+([0-9.e]+)' --replace '$1' <<< "$DBSYNC_METRICS")

                        # Bash and bc don't easily handle exponents which is the format prometheus metrics are provided in
                        BLOCK_DIFF=$(awk "BEGIN {print $NODE_BLOCK_HEIGHT - $DBSYNC_BLOCK_HEIGHT}")

                        if [ "$BLOCK_DIFF" -gt "${toString cfg.blockDiffTolerance}" ]; then
                          echo "Cardano-db-sync is lagging behind node more than $BLOCK_DIFF blocks which is beyond the allowed tolerance of ${toString cfg.blockDiffTolerance} blocks, aborting with a failure status."
                          exit 1
                        fi
                        echo "Cardano-db-sync is $BLOCK_DIFF blocks behind node which is within the allowed tolerance of ${toString cfg.blockDiffTolerance} blocks."

                        touch "$RUNNING_FILE"

                        echo "Obtaining last snapshot name:"
                        OLD_SNAPSHOT=$({ ls -tr1 db-sync-snapshot*.tgz 2> /dev/null || echo "NO_SNAPSHOT_FOUND"; } | tail -n 1)
                        echo "Last snapshot name: $OLD_SNAPSHOT"

                        echo "Starting snapshot creation -- expect this to take awhile..."
                        systemctl stop cardano-db-sync

                        echo "Snapshot creation completed, restarting cardano-db-sync service."
                        systemctl start cardano-db-sync \

                        echo "Obtaining new snapshot name."
                        NEW_SNAPSHOT=$({ ls -tr1 db-sync-snapshot*.tgz 2> /dev/null || echo "NO_SNAPSHOT_FOUND"; } | tail -n 1)
                        echo "New snapshot name: $NEW_SNAPSHOT"

                        if [ "$NEW_SNAPSHOT" != "$OLD_SNAPSHOT" ]; then
                          SCHEMA=$(rg --only-matching 'schema-([0-9]+\.[0-9]+)-block' --replace '$1' <<< "$NEW_SNAPSHOT")

                          echo "Checking the snapshot sha256 hash matches the snapshot..."
                          sha256sum -c "$NEW_SNAPSHOT".sha256sum

                          for ARTIFACT in "$NEW_SNAPSHOT".sha256sum "$NEW_SNAPSHOT"; do
                            echo "Pushing artifact $ARTIFACT to s3://${cfg.bucket}/${cfg.prefix}/$SCHEMA/"
                            s3cmd put \
                              --acl-public \
                              --multipart-chunk-size-mb=512 \
                              "$ARTIFACT" \
                              "s3://${cfg.bucket}/${cfg.prefix}/$SCHEMA/"
                            echo "Push completed; file may be downloaded from: http://${cfg.bucket}.s3.amazonaws.com/${cfg.prefix}/$SCHEMA/$ARTIFACT"
                          done
                          echo "Snapshot push complete."
                        else
                          echo "Something went wrong, the new snapshot name is the same as the old snapshot name: $OLD_SNAPSHOT, aborting with a failure status."
                          exit 1
                        fi
                      else
                        echo "A snapshot and upload appears to already be in progress, skipping."
                      fi
                    else
                      rm -f "$RUNNING_FILE"
                    fi
                  '';
                });

                # The cardano-db-sync snapshot may take several hours and
                # if bandwidth for upload is reduced, pushing the snapshot may
                # take another several hours.
                TimeoutStartSec = 24 * 3600;
              };
            };
          };

          timers.cardano-db-sync-snapshots = {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = "hourly";
              Unit = "cardano-db-sync-snapshots.service";
            };
          };
        };

        sops.secrets = mkIf cfg.useSopsSecrets (mkSopsSecret (mkSopsSecretParams "cardano-db-sync-snapshots" "${name}-snapshots"));
      };
    };
}
