{inputs, ...}: {
  flake.nixosModules.ami = nixos @ {
    config,
    pkgs,
    lib,
    ...
  }: let
    inherit (builtins) floor toString;
    inherit (lib) mkIf mkOption types;
    inherit (types) float ints nullOr oneOf;

    # When building standalone AMI, nodeResources won't be in the module args
    memMiB = nixos.nodeResources.memMiB or null;

    # Calculate ARC max in bytes from percentage
    calcArcMaxBytes = zfsArcPct:
      if memMiB == null || zfsArcPct == null
      then null
      else floor (memMiB * 1024 * 1024 * zfsArcPct / 100.0);
  in {
    imports = [
      "${inputs.nixpkgs}/nixos/maintainers/scripts/ec2/amazon-image.nix"
    ];

    options = {
      boot.zfs.zfsArcPct = mkOption {
        type = nullOr (oneOf [ints.positive float]);
        default = 5.0;
        description = ''
          Percentage of total memory to allocate for ZFS ARC cache.

          Default: 5.0

          The ZFS ARC (Adaptive Replacement Cache) is ZFS's intelligent cache system.
          Setting this too high may starve other applications; too low may reduce ZFS performance.

          Set to null to disable setting zfs_arc_max (ZFS will use its own defaults).

          Minimum enforced by ZFS: 64 MiB
        '';
      };
    };

    config = let
      arcMaxBytes = calcArcMaxBytes config.boot.zfs.zfsArcPct;
    in {
      # Set ZFS ARC max size via kernel parameter
      boot.kernelParams = mkIf (config.boot.zfs.zfsArcPct != null) [
        "zfs.zfs_arc_max=${toString arcMaxBytes}"
      ];

      ec2 = {
        efi = true;

        zfs = {
          enable = true;
          datasets = {
            "tank/reserved".properties = {
              canmount = "off";
              refreserv = "1G";
            };
            "tank/root".mount = "/";
            "tank/nix".mount = "/nix";
            "tank/home".mount = "/home";
            "tank/state".mount = "/state";
          };
        };
      };

      systemd.services = {
        # `services.zfs.expandOnBoot` expands the partitions but does not trigger actual expansion.
        "zpool-expand@" = {
          path = [pkgs.jq];
          script = ''
            for dev in $(
              zpool status -L --json \
              | jq --raw-output '.pools.tank.vdevs[].vdevs[].name'
            ); do
              # No need for `-e` as the pool has `autoexpand=on`.
              zpool online tank "$dev"
            done
          '';
        };

        zfs-blank = {
          wantedBy = ["sysinit.target"];
          before = ["sysinit.target"];

          path = [config.boot.zfs.package];

          script = ''
            zfs snapshot -r tank/{root,home}@blank || :
            zfs hold -r blank tank/{root,home}@blank || :
          '';

          unitConfig.DefaultDependencies = false;

          serviceConfig.Type = "oneshot";
        };
      };

      assertions = let
        arcMaxBytes = calcArcMaxBytes config.boot.zfs.zfsArcPct;
      in [
        {
          assertion = config.boot.zfs.zfsArcPct == null || (config.boot.zfs.zfsArcPct > 0 && config.boot.zfs.zfsArcPct <= 100);
          message = ''
            boot.zfs.zfsArcPct must be between 0 and 100 (got ${toString config.boot.zfs.zfsArcPct}), or null to disable.
            This represents the percentage of total memory to allocate to ZFS ARC cache.
          '';
        }
        {
          assertion = arcMaxBytes == null || arcMaxBytes >= 67108864; # 64 MiB minimum
          message = ''
            boot.zfs.zfsArcPct results in an ARC size that is too small.
            Minimum: 67108864 bytes (64 MiB)
            Current calculated value: ${toString arcMaxBytes} bytes
            Total memory: ${toString memMiB} MiB
            Configured percentage: ${toString config.boot.zfs.zfsArcPct}%

            Consider increasing boot.zfs.zfsArcPct or ensuring the machine has sufficient memory.
          '';
        }
      ];
    };
  };
}
