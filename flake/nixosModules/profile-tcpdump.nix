# nixosModule: profile-tcpdump
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.tcpdump.bucketName
#   config.services.tcpdump.bucketRegion
#   config.services.tcpdump.environmentFile
#   config.services.tcpdump.group
#   config.services.tcpdump.ports
#   config.services.tcpdump.prefix
#   config.services.tcpdump.rotateSeconds
#   config.services.tcpdump.user
#   config.services.tcpdump.useSopsSecrets
#
# Tips:
#   * This is a cardano-node add-on to the cardano-parts profile-cardano-parts nixos service module
#   * This module provides tcpdump and pcap storage functionality for a declared list of ports
#   * The cardano-parts profile-cardano-parts nixos service module should still be imported separately
flake: {
  flake.nixosModules.profile-tcpdump = {
    config,
    pkgs,
    lib,
    name,
    ...
  }: let
    inherit (lib) getExe listToAttrs mkIf mkOption types;
    inherit (types) bool ints listOf port str;
    inherit (groupCfg) groupFlake groupName;
    inherit (opsLib) mkSopsSecret;

    groupCfg = config.cardano-parts.cluster.group;
    groupOutPath = groupFlake.self.outPath;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

    cfg = config.services.tcpdump;
  in {
    key = ./profile-tcpdump.nix;

    options = {
      services.tcpdump = {
        bucketName = mkOption {
          type = types.str;
          default = null;
          description = "The name of the bucket to store tcpdump pcaps in.";
        };

        bucketRegion = mkOption {
          type = types.str;
          default = "eu-central-1";
          description = "The region that the bucket resides in.";
        };

        group = mkOption {
          type = str;
          default = "root";
          description = ''
            The group of the tcpdump service.
            The default group is root in order to capture packets from network interfaces.
          '';
        };

        ports = mkOption {
          type = listOf port;
          default = [3001];
        };

        prefix = mkOption {
          type = str;
          default = null;
          example = "cardano-node";
          description = ''
            The prefix in the bucket which tcpdump pcaps will be pushed to.

            The actual destination path for a pcap file will be:
              s3://''${cfg.bucket}/''${cfg.prefix}/"
          '';
        };

        rotateSeconds = mkOption {
          type = ints.positive;
          default = 60 * 10;
        };

        environmentFile = mkOption {
          type = str;
          default =
            if cfg.useSopsSecrets
            then config.sops.secrets.tcpdump.path
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

            An auto-expire lifecycle should also be applied so old tcpdump pcaps don't accumulate.

              $ aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --output json
              {
                  "Rules": [
                      {
                          "Expiration": {
                              "Days": 30
                          },
                          "ID": "Delete old pcaps in $PREFIX prefix",
                          "Filter": {
                              "Prefix": "$PREFIX/"
                          },
                          "Status": "Enabled",
                          "AbortIncompleteMultipartUpload": {
                              "DaysAfterInitiation": 30
                          }
                      }
                  ]
              }
          '';
        };

        user = mkOption {
          type = str;
          default = "root";
          description = ''
            The user of the tcpdump service.
            The default user is root in order to capture packets from network interfaces.
          '';
        };

        useSopsSecrets = mkOption {
          type = bool;
          default = true;
          description = ''

            Whether to use the default configurated sops secrets if true,
            or user deployed secrets if false.

            If false, the secrets file will need to be provided to the target
            machine either by additional module code or out of band and the
            following option should be set with this secret file's path:

              config.services.tcpdump.environmentFile

            For consistency with sops secrets, a suggested secrets path is:

              /run/secrets/tcpdump
          '';
        };
      };
    };

    config = {
      systemd.services =
        listToAttrs (
          map (
            port: {
              name = "tcpdump-${toString port}";
              value = {
                description = "Capture packet traffic on port ${toString port}";
                wantedBy = ["multi-user.target"];

                startLimitIntervalSec = 10;
                startLimitBurst = 10;

                serviceConfig = {
                  User = cfg.user;
                  Group = cfg.group;

                  Restart = "always";
                  StateDirectory = "tcpdump";
                  WorkingDirectory = "/var/lib/tcpdump";

                  ExecStart = getExe (pkgs.writeShellApplication {
                    name = "tcpdump-${toString port}";
                    runtimeInputs = with pkgs; [inetutils tcpdump];
                    bashOptions = ["errexit" "nounset" "pipefail" "xtrace"];

                    text = ''
                      PCAP_DIR="$(hostname)_${toString port}"
                      mkdir -p "$PCAP_DIR"
                      cd "$PCAP_DIR"

                      tcpdump \
                        -i any \
                        -w '%Y-%m-%d_%H:%M:%S.pcap' \
                        -G ${toString cfg.rotateSeconds} \
                        -n 'port ${toString port}'
                    '';
                  });
                };
              };
            }
          )
          cfg.ports
        )
        // {
          tcpdump-upload = {
            wantedBy = ["multi-user.target"];
            after = ["tcpdump.service"];

            startLimitIntervalSec = 10;
            startLimitBurst = 10;

            serviceConfig = {
              User = cfg.user;
              Group = cfg.group;

              EnvironmentFile = cfg.environmentFile;

              Restart = "always";
              StateDirectory = "tcpdump";
              WorkingDirectory = "/var/lib/tcpdump";

              # Fd now includes a leading `./` in the parent directory output
              # `{//}` which is undesirable in the s3 path. Since piping `{//}`
              # to sed or similar cmds doesn't work with --exec in or out of a
              # shell and neither does passing a function or alias, we'll pass
              # the output to a script that is included in the path as the next
              # best alternative.
              ExecStart = let
                move-to-s3 = pkgs.writeShellApplication {
                  name = "move-to-s3";
                  runtimeInputs = with pkgs; [awscli2 gnused];
                  text = ''
                    FULL_PATH="$1"
                    DIRNAME=$(dirname "$FULL_PATH" | sed 's|./||g')
                    BASENAME=$(basename "$FULL_PATH")
                      aws --region ${cfg.bucketRegion} s3 mv "$FULL_PATH" "s3://${cfg.bucketName}/${cfg.prefix}/$DIRNAME/$BASENAME"
                  '';
                };
              in
                getExe (pkgs.writeShellApplication {
                  name = "tcpdump-upload";
                  runtimeInputs = with pkgs; [fd move-to-s3];
                  bashOptions = ["errexit" "nounset" "pipefail" "xtrace"];
                  text = ''
                    while true; do
                      fd --extension pcap --changed-before='${toString (cfg.rotateSeconds * 2)} seconds' --threads 1 --exec move-to-s3 {}
                      sleep 60
                    done
                  '';
                });
            };
          };
        };

      sops.secrets = mkIf cfg.useSopsSecrets (mkSopsSecret {
        secretName = "tcpdump";
        keyName = "${name}-tcpdump";
        inherit groupOutPath groupName;
        fileOwner = cfg.user;
        fileGroup = cfg.group;
        restartUnits = ["tcpdump-upload.service"];
      });
    };
  };
}
