# nixosModule: profile-cardano-postgres
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-postgres.dataDir
#   config.services.cardano-postgres.maxConnections
#   config.services.cardano-postgres.ramAvailableMiB
#   config.services.cardano-postgres.socketPath
#   config.services.cardano-postgres.withHighCapacityPostgres
#   config.services.cardano-postgres.withPgStatStatements
{
  flake.nixosModules.profile-cardano-postgres = {
    config,
    nodeResources,
    pkgs,
    lib,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) bool float ints nullOr oneOf str;
      inherit (nodeResources) cpuCount memMiB;

      connScale = 1.0 * 20 / cfg.maxConnections;
      cpuScale =
        if cpuCount <= 4
        then 1.0
        else if cpuCount >= 8
        then (1.0 / 2)
        else (1.0 * 4 / cpuCount);
      fromFloat = f: toString (roundFloat f);
      numCeil = ram: ceiling:
        if ram < ceiling
        then ram
        else ceiling;
      numFloor = ram: floor:
        if ram > floor
        then ram
        else floor;
      ramScale = base: base * (max (1.0 * cfg.ramAvailableMiB / 1024) 1);
      roundFloat = f:
        if f >= (floor f + 0.5)
        then ceil f
        else floor f;

      cfg = config.services.cardano-postgres;
    in {
      options = {
        services.cardano-postgres = {
          dataDir = mkOption {
            description = "The directory for postgresql data.  If null, this parameter is not configured.";
            type = nullOr str;
            default = null;
          };

          maxConnections = mkOption {
            description = "The postgresql maximum number of connections to allow, between 20 and 9999";
            type = ints.between 20 9999;
            default = 200;
          };

          ramAvailableMiB = mkOption {
            description = "The default RAM available for postgresql on the machine in MiB.";
            type = oneOf [ints.positive float];
            default = memMiB * 0.70;
          };

          socketPath = mkOption {
            description = "The postgresql socket path to use, typically `/run/postgresql`.";
            type = str;
            default = "/run/postgresql";
          };

          withHighCapacityPostgres = mkOption {
            description = "Configure postgresql to use additional resources to support high RAM and connection requirements.";
            type = bool;
            default = false;
          };

          withPgStatStatements = mkOption {
            description = ''
              Configure pg_stat_statements which allow performance tracking of queries.
              During non-IO bound runtime, this may impact performance up to ~10%.
            '';
            type = bool;
            default = true;
          };
        };
      };

      config = {
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_15;
          dataDir = mkIf (cfg.dataDir != null) cfg.dataDir;
          enableTCPIP = false;
          settings =
            {
              # Optimized for:
              # DB Version: 15
              # OS Type: linux
              # DB Type: web
              # With scaling factors and relationships interpolated from: https://pgtune.leopard.in.ua/
              max_connections = cfg.maxConnections;
              shared_buffers = "${fromFloat (ramScale 256)}MB";
              effective_cache_size = "${fromFloat (ramScale 768)}MB";
              maintenance_work_mem = "${fromFloat (numCeil (ramScale 64) 2048)}MB";
              checkpoint_completion_target = 0.9;
              wal_buffers = "${fromFloat (numCeil (ramScale 7864) (16 * 1024))}kB";
              default_statistics_target = 100;
              random_page_cost = 1.1;
              effective_io_concurrency = 200;
              work_mem = "${fromFloat (numFloor ((ramScale 6553) * connScale * cpuScale) 64)}kB";
              huge_pages =
                if memMiB >= 32 * 1024
                then "try"
                else "off";
              min_wal_size = "1GB";
              max_wal_size = "4GB";
            }
            // optionalAttrs (cpuCount >= 4) {
              max_worker_processes = numCeil cpuCount 16;
              max_parallel_workers_per_gather = 2;
              max_parallel_workers = numCeil cpuCount 16;
              max_parallel_maintenance_workers = 2;
            }
            // optionalAttrs cfg.withPgStatStatements {
              shared_preload_libraries = "pg_stat_statements";
              "pg_stat_statements.track" = "all";
            };
        };
      };
    };
}
