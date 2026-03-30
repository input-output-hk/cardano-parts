{inputs, ...}: {
  flake.nixosModules.ami = {
    config,
    pkgs,
    ...
  }: {
    imports = [
      "${inputs.nixpkgs}/nixos/maintainers/scripts/ec2/amazon-image.nix"
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
  };
}
