# nixosModule: profile-zfs-snapshots
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.zfs-snapshots.dataset
#   config.services.zfs-snapshots.keep
#   config.services.zfs-snapshots.onCalendar
#   config.services.zfs-snapshots.prefix
#
# Tips:
#   * This module provides rolling, crash-consistent ZFS snapshots of a dataset
#     on a timer, pruned to a fixed count -- giving a `keep * cadence`
#     point-in-time recovery window
#
#   * This is useful on any cluster for recovering transient on-disk state,
#     eg: a service's working or volatile data, hours after the fact, by which
#     time the live copy has usually been overwritten
#
#   * Snapshots are whole-dataset, crash-consistent and cheap copy-on-write
#
#   * Snapshot recovery:
#       zfs list -t snapshot -o name,creation -s creation | grep "<dataset>@<prefix>"
#       mkdir -p /mnt/snap && mount -t zfs <dataset>@<prefix>-<ts> /mnt/snap
#       # ...or browse it in-place under <dataset-mountpoint>/.zfs/snapshot/<name>/
{
  flake.nixosModules.profile-zfs-snapshots = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) escapeShellArg getExe mkOption;
    inherit (lib.types) ints str;

    cfg = config.services.zfs-snapshots;
  in {
    key = ./profile-zfs-snapshots.nix;

    options.services.zfs-snapshots = {
      dataset = mkOption {
        type = str;
        default = "tank/root";
        description = ''
          ZFS dataset to snapshot. Defaults to `tank/root`, the usual
          cardano-parts root dataset (which holds /var/lib and thus most
          service state). If the data you care about isn't its own dataset,
          the whole root is snapshotted -- cheap via copy-on-write.
        '';
      };

      keep = mkOption {
        type = ints.positive;
        default = 72;
        description = ''
          Number of recent prefixed snapshots to retain. With the default
          20-minute cadence, 72 snapshots is approximately a 24 hour recovery
          window.
        '';
      };

      onCalendar = mkOption {
        type = str;
        default = "*:0/20";
        description = "systemd `OnCalendar` cadence. Default: every 20 minutes.";
      };

      prefix = mkOption {
        type = str;
        default = "autosnap";
        description = "Snapshot name prefix. Only snapshots with this prefix are pruned by this module.";
      };
    };

    config = {
      systemd.services.zfs-snapshots = {
        description = "Rolling ZFS snapshot of ${cfg.dataset} for point-in-time recovery";

        # Only meaningful once the pool is mounted.
        after = ["zfs-mount.service"];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe (pkgs.writeShellApplication {
            name = "zfs-snapshots";
            runtimeInputs = with pkgs; [config.boot.zfs.package coreutils gnugrep];
            text = ''
              dataset=${escapeShellArg cfg.dataset}
              prefix=${escapeShellArg cfg.prefix}
              keep=${toString cfg.keep}

              # No-op cleanly if the dataset isn't present (e.g. before first import).
              if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
                echo "zfs-snapshots: dataset $dataset not found, skipping" >&2
                exit 0
              fi

              stamp=$(date -u +%Y%m%dT%H%M%SZ)
              zfs snapshot "$dataset@$prefix-$stamp"
              echo "zfs-snapshots: created $dataset@$prefix-$stamp"

              # Prune: keep the newest $keep snapshots with our prefix, destroy older.
              # `-s creation` lists oldest-first; drop the trailing $keep from deletion.
              # Only snapshots with our prefix are considered (other snapshots, incl.
              # any `@blank`/manual baselines, are never touched).
              mapfile -t toPrune < <(
                zfs list -H -t snapshot -o name -s creation \
                  | { grep -F "$dataset@$prefix-" || true; } \
                  | head -n "-$keep"
              )
              for snap in "''${toPrune[@]}"; do
                echo "zfs-snapshots: pruning $snap"
                zfs destroy "$snap"
              done
            '';
          });
        };
      };

      systemd.timers.zfs-snapshots = {
        description = "Schedule rolling ZFS snapshots for point-in-time recovery";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.onCalendar;
          Persistent = true;
          RandomizedDelaySec = "30s";
        };
      };
    };
  };
}
