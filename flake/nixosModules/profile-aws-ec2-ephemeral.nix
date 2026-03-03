# nixosModule: profile-aws-ec2-ephemeral
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.aws.ec2.ephemeral.enablePostMountService
#   config.services.aws.ec2.ephemeral.fsOpts
#   config.services.aws.ec2.ephemeral.fsType
#   config.services.aws.ec2.ephemeral.label
#   config.services.aws.ec2.ephemeral.mountPoint
#   config.services.aws.ec2.ephemeral.postMountScript
#   config.services.aws.ec2.ephemeral.postMountServiceName
#   config.services.aws.ec2.ephemeral.raidCfgFile
#   config.services.aws.ec2.ephemeral.raidDevice
#   config.services.aws.ec2.ephemeral.serviceName
#   config.services.aws.ec2.ephemeral.specialEphemeralInstanceTypePrefixes
#   config.services.aws.ec2.ephemeral.symlinkTarget
#
# Tips:
#   * This module modifies handles formatting and mounting of single or
#     multiple NVMe ephemeral block devices in aws ec2.
#
#   * This module creates a RAID0 array if multiple ephemeral block devices are
#     available.
#
# Notes:
#   A number of approaches for mounting ephemeral aws ec2 instance
#   storage run into complications, such as:
#
#   * The simplest approach would be to use a small nixos `fileSystems`
#   declaration with a kernel discovered device name and auto-format.
#   However, device name assignments are non-deterministic and often change
#   during subsequent reboots causing mount failures.
#
#   * If RAID is not needed, another approach might be to create sorted and
#   predictable symlink names to ephemeral block devices with udev rules and
#   a helper script using a sort index such as serial number. However,
#   predictable ordering becomes problematic as udev rules are called with
#   each block device discovery instead of after settlement.
#
#   * If an approach of fstab entry with systemd service hook is used, ie,
#   via nixos `fileSystems` with appropriate options set where systemd is
#   leveraged to create ordered symlinks for fstab to mount, systemd fails to
#   recognize the symlinked devices and mount them properly.
#
#   Writing a systemd unit to handle all formatting, mounting and
#   unmounting logic for ephemeral devices, including implementing any RAID
#   requirements, could be done but would duplicate nixos `fileSystems` effects
#   and remains less transparent while not in fstab.
#
#   An acceptable compromise appears to be a systemd service that handles
#   ephemeral block device formatting with label assignment and then
#   leverages nixos `fileSystems` to handle discovery (ie: fstab), mounting
#   and unmounting tasks via label attribute.
{
  flake.nixosModules.profile-aws-ec2-ephemeral = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (builtins) head;
    inherit (lib) any getExe hasInfix hasPrefix mkForce mkIf mkOption removePrefix splitString;
    inherit (lib.types) bool enum listOf str;
    inherit (config.aws.instance) instance_type;

    isDiskBackedStorageType = t: hasInfix "d" (head (splitString "." t));
    isSpecialType = t: any (_: _) (map (e: hasPrefix e t) cfg.specialEphemeralInstanceTypePrefixes);

    # NVMe containing ephemeral instance types generally need to have a "d" in
    # the instance type, or belong to a special class.
    hasEphemeral = isDiskBackedStorageType instance_type || isSpecialType instance_type;

    cfg = config.services.aws.ec2.ephemeral;
  in {
    key = ./profile-aws-ec2-ephemeral.nix;

    options.services.aws.ec2.ephemeral = {
      enableMountOnCreation = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to ensure the ephemeral volume is mounted automatically after
          it becomes available.
        '';
      };

      enablePostMountService = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to enable post mounting service handling.
        '';
      };

      fsOpts = mkOption {
        type = listOf str;
        default =
          if cfg.fsType == "ext2"
          then [
            # An example file system performance tuning option for ext2
            "noacl"
            "noatime"
            "nodiratime"
          ]
          else if cfg.fsType == "xfs"
          then [
            # An example file system performance tuning option for XFS
            "logbsize=256k"
          ]
          else [];
        description = ''
          File system tuning options used during mounting.
        '';
      };

      fsType = mkOption {
        type = enum ["ext2" "xfs"];
        default = "ext2";
        description = ''
          The file system to use for ephemeral storage.

          The block devices will be formatted with this file system. If the
          file system is to be changed, the instance will need to be
          re-deployed and then stopped and restarted to re-instantiate the
          ephemeral block device(s) at which point auto-format and relabelling
          will occur.

          NOTE: Changing to a file system other than ext2 or xfs will require
          extending the nixos module code to support the new filesystem(s).
        '';
      };

      label = mkOption {
        type = str;
        default = "ephemeral";
        description = ''
          The block device label to be applied to the ephemeral storage file
          system.

          Mounting by label allows the underlying device to be either a
          direct NVMe block device or a RAID array.
        '';
      };

      mountPoint = mkOption {
        type = str;
        default = "/ephemeral";
        description = ''
          The location to mount ephemeral storage.
        '';
      };

      postMountScript = mkOption {
        type = str;
        default =
          if (config.services ? cardano-node && config.services.cardano-node.enable)
          then ''
            mkdir -p ${cfg.mountPoint}/cardano-node
            chown -R cardano-node:cardano-node ${cfg.mountPoint}/cardano-node
          ''
          else ''
            echo "Cardano node module not detected, exiting."
          '';
        description = ''
          Default post ephemeral block device mount script code, to be embedded
          inside a bash writeShellApplication wrapper.
        '';
      };

      postMountServiceName = mkOption {
        type = str;
        default = "ephemeral-post-mount";
        description = ''
          The systemd service name for post mount set up, excluding the
          `.service` suffix.
        '';
      };

      raidCfgFile = mkOption {
        type = str;
        default = "/etc/mdadm/mdadm.conf";
        description = ''
          The dynamically created and mutable raid configuration file for
          ephemeral storage.
        '';
      };

      raidDevice = mkOption {
        type = str;
        default = "/dev/md127";
        description = ''
          RAID often reverts to /dev/md127 due to auto scan and assemble
          despite proper use of /etc/mdadm.conf, so to avoid device index
          switching, default to use of the autoscan index from the time of
          RAID array creation.
        '';
      };

      serviceName = mkOption {
        type = str;
        default = "ephemeral-setup";
        description = ''
          The systemd service name for formatting ephemeral block devices,
          excluding the `.service` suffix.
        '';
      };

      specialEphemeralInstanceTypePrefixes = mkOption {
        type = listOf str;
        default = ["i3" "i7" "trn1"];
        description = ''
          Aws ec2 instance type prefixes which contain ephemeral NVMe block
          devices without also containing the standard `d` identifier in the
          instance type for disk backed storage.
        '';
      };

      symlinkTarget = mkOption {
        type = str;
        default = "/dev/ephemeral";
        description = ''
          The symlink target linking to the ephemeral block storage file system.
        '';
      };
    };

    config = mkIf hasEphemeral {
      fileSystems = {
        "${cfg.label}" = {
          inherit (cfg) fsType label mountPoint;

          # The systemd service will handle the formatting logic.
          autoFormat = false;

          options =
            [
              # Wait until systemd ephemeral setup is complete so the file system will exist.
              "x-systemd.requires=${cfg.serviceName}.service"
              "x-systemd.after=${cfg.serviceName}.service"

              # Required to avoid systemd order cycling problems that otherwise occur.
              # The ephemeral file system will be auto-mounted on the first access attempt.
              "x-systemd.automount"
            ]
            ++ cfg.fsOpts;
        };
      };

      # Make /etc/mdadm.conf reflect the dynamically created mutable raid
      # config file.
      environment.etc."mdadm.conf".source = mkForce cfg.raidCfgFile;

      systemd.services = {
        ${cfg.serviceName} = {
          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe (pkgs.writeShellApplication {
              name = cfg.serviceName;

              runtimeInputs = with pkgs; [e2fsprogs fd jq kmod mdadm util-linux xfsprogs];
              text = ''
                set -euo pipefail

                LABEL="${cfg.label}"
                RAID_CFG="${cfg.raidCfgFile}"
                RAID_DEV="${cfg.raidDevice}"
                SYM_TGT="${cfg.symlinkTarget}"

                IS_EMPTY() {
                  DEV="$1"
                  RESULT=$(lsblk --fs --json "$DEV" \
                    | jq -r 'any(.blockdevices[]; (has("children") | not) and (.fstype == null))')

                  if [ "$RESULT" = "true" ]; then
                    return 0
                  else
                    return 1
                  fi
                }

                mapfile -t INSTANCE_BD < <(fd 'nvme-Amazon_EC2_NVMe_Instance_Storage_AWS[0-9A-F]{17}$' /dev/disk/by-id/ | sort)
                NUM_BD="''${#INSTANCE_BD[@]}"

                echo "Number of ephemeral block devices detected are: $NUM_BD, comprised of:"
                printf "%s\n" "''${INSTANCE_BD[@]}"

                # Check ephemeral storage is available
                if [ "$NUM_BD" -eq "0" ]; then
                  echo "No ephemeral block devices found, aborting."
                  exit 0
                fi

                # Check if all ephemeral storage is empty
                EMPTY="true"
                for DEV in "''${INSTANCE_BD[@]}"; do
                  if ! IS_EMPTY "$DEV"; then
                    echo "Device $DEV has a file system or holds partitions."
                    EMPTY="false"
                  fi
                done

                if [ "$EMPTY" = "false" ]; then
                  echo "One or more ephemeral block devices are not empty; symlinking only..."
                else
                  echo "Ephemeral block device(s) appear to be empty, formatting and symlinking..."
                fi

                # Create the filesystem and symlink as applicable
                if [ "$NUM_BD" -eq "1" ]; then
                  if [ "$EMPTY" = "true" ]; then
                    set -x
                    mkfs -t ${cfg.fsType} -L "$LABEL" "''${INSTANCE_BD[@]}"
                  fi
                  ln -svf "''${INSTANCE_BD[@]}" "$SYM_TGT"
                  set +x
                elif [ "$NUM_BD" -gt "1" ]; then
                  echo "Multiple ephemeral block devices are available..."
                  if [ "$EMPTY" = "true" ]; then
                    set -x
                    mdadm --create "$RAID_DEV" --raid-devices="$NUM_BD" --level=0 "''${INSTANCE_BD[@]}"
                    mdadm --detail --scan | tee "$RAID_CFG"
                    mkfs -t ${cfg.fsType} -L "$LABEL" "$RAID_DEV"
                    ln -svf "$RAID_DEV" "$SYM_TGT"
                    set +x
                  else
                    if [ -b "$RAID_DEV" ]; then
                      ln -svf "$RAID_DEV" "$SYM_TGT"
                    fi
                  fi
                  exit 0
                else
                  echo "The number of ephemeral block devices was not properly recognized: $NUM_BD"
                  exit 1
                fi
              '';
            });
          };
        };

        ${cfg.postMountServiceName} = {
          after = ["${cfg.label}.mount"];
          requires = ["${cfg.label}.mount"];
          wantedBy = ["${cfg.label}.mount"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe (pkgs.writeShellApplication {
              name = cfg.serviceName;
              text = ''
                set -euo pipefail

                ${cfg.postMountScript}
              '';
            });
          };
        };

        "${cfg.serviceName}-mount-on-creation" = mkIf cfg.enableMountOnCreation {
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe (pkgs.writeShellApplication {
              name = "${cfg.serviceName}-mount-on-creation";
              text = ''
                set -euo pipefail

                while true; do
                  echo "Sleeping 10 seconds until mount on created attempt..."
                  sleep 10
                  # shellcheck disable=SC2010
                  if ls -1 / | grep -q ${removePrefix "/" cfg.mountPoint}; then
                    echo "Found: ${cfg.mountPoint}"

                    # Trigger the systemd auto-mount service
                    ls ${cfg.mountPoint}

                    touch ${cfg.mountPoint}/.mounted

                    break
                  fi
                done
              '';
            });
          };
        };
      };
    };
  };
}
