# nixosModule: profile-cardano-postgres
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-postgres.dataDir
#   config.services.cardano-postgres.maxConnections
#   config.services.cardano-postgres.ramAvailableMiB
#   config.services.cardano-postgres.socketPath
#   config.services.cardano-postgres.withPgStatStatements
#
# Tips:
#   * This is a cardano-postgres profile to configure the postgresql nixos service
#   * This module assists with optimizing postgres for use with dbsync through parameter tuning
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

      psqlrc = toFile "psqlrc" ''
        \timing on

        -- Set statements can't be multiline
        \set show_behind_by_time_of 'SELECT now () - MAX (time) AS behind_by FROM block;'
        \set show_conninfo 'select usename, count(*) from pg_stat_activity group by usename;'
        \set show_current_epoch 'SELECT MAX (no) FROM epoch;'
        \set show_prepared_statements 'select * from pg_prepared_statements;'
        \set show_running_queries 'SELECT pid, age(clock_timestamp(), query_start), usename, query FROM pg_stat_activity WHERE query != \'<IDLE>\' AND query NOT ILIKE \'%pg_stat_activity%\' ORDER BY query_start desc;'

        -- Prepared statements should only be executed if the schema has already migrated
        -- This can be verified by checking stage_three of schema_version is non-zero
        -- Ref: https://github.com/input-output-hk/cardano-db-sync/blob/master/doc/schema.md#schema_version
        DO $$
        BEGIN
          IF (select true from pg_tables where tablename = 'schema_version') THEN
            IF (select stage_three from schema_version) > 0 THEN
              -- Prepared statements for longer queries and functions
              DEALLOCATE ALL;

              -- Show the number of blocks made per epoch across all epochs by one pool
              PREPARE show_pool_block_history_by_epoch_fn (varchar) AS
                SELECT block.epoch_no, count (*) AS block_count FROM block
                  INNER JOIN slot_leader ON block.slot_leader_id = slot_leader.id
                  INNER JOIN pool_hash ON slot_leader.pool_hash_id = pool_hash.id
                  WHERE pool_hash.view = $1
                  GROUP BY block.epoch_no, pool_hash.view
                  ORDER BY epoch_no desc;

              -- Show the blocks made in one epoch by one pool
              PREPARE show_pool_block_history_in_epoch_fn (word31type, varchar) AS
                SELECT block.block_no, block.epoch_no, pool_hash.view AS pool_view FROM block
                  INNER JOIN slot_leader ON block.slot_leader_id = slot_leader.id
                  INNER JOIN pool_hash ON slot_leader.pool_hash_id = pool_hash.id
                  WHERE block.epoch_no = $1
                  AND pool_hash.view = $2
                  ORDER BY block_no DESC;

              -- Show the number of blocks made in one epoch by all pools along with corresponding delegation amount
              PREPARE show_pools_block_history_in_epoch_fn (word31type) AS
                WITH
                  active_pools AS (
                    SELECT pool_hash.view, pool_hash.id FROM pool_update
                      INNER JOIN pool_hash ON pool_update.hash_id = pool_hash.id
                      WHERE registered_tx_id IN (SELECT MAX (registered_tx_id) FROM pool_update GROUP BY hash_id)
                      AND NOT EXISTS (
                        SELECT * FROM pool_retire WHERE pool_retire.hash_id = pool_update.hash_id
                        AND pool_retire.retiring_epoch <= $1
                      )
                    ),
                  pools_deleg_sum AS (
                    SELECT pool_hash.view, SUM(amount) AS lovelace_delegated FROM epoch_stake
                      INNER JOIN pool_hash ON epoch_stake.pool_id = pool_hash.id
                      WHERE epoch_no = $1 GROUP BY pool_hash.id
                    )
                SELECT active_pools.view, (
                  SELECT COUNT (*) FROM block
                    INNER JOIN slot_leader ON block.slot_leader_id = slot_leader.id
                    INNER JOIN pool_hash ON slot_leader.pool_hash_id = pool_hash.id
                    WHERE pool_hash.id = active_pools.id
                    AND block.epoch_no = $1
                  ), (
                    SELECT lovelace_delegated FROM pools_deleg_sum
                    WHERE pools_deleg_sum.view = active_pools.view
                  )
                  FROM active_pools
                  ORDER by view;

              -- Show pool info for a single pool, best viewed in extended view mode, \x
              PREPARE show_pool_info_fn AS
                SELECT
                  ph.view AS pool_hash_view, ph.hash_raw AS pool_hash_hash_raw,
                  pmr.url AS pool_metadata_ref_url, pmr.hash AS pool_metadata_ref_hash, pmr.registered_tx_id AS pool_metadata_ref_registered_tx_id,
                  pr.ipv4 AS pool_relay_ipv4, pr.ipv6 AS pool_relay_ipv6, pr.dns_name AS pool_relay_dns_name, pr.dns_srv_name AS pool_relay_dns_srv_name, pr.port AS pool_relay_port,
                  prt.cert_index AS pool_retire_cert_index, prt.announced_tx_id AS pool_retire_announced_tx_id, prt.retiring_epoch AS pool_retire_retiring_epoch,
                  pu.id AS pool_update_id, pu.cert_index AS pool_update_cert_index, pu.vrf_key_hash AS pool_update_vrf_key_hash,
                  pu.pledge AS pool_update_pledge, pu.active_epoch_no AS pool_update_active_epoch_no, pu.meta_id AS pool_update_meta_id,
                  pu.margin AS pool_update_margin, pu.fixed_cost AS pool_update_fixed_cost, pu.registered_tx_id AS pool_update_registered_tx_id,
                  sao.view AS stake_address_owner_view, sao.hash_raw AS stake_address_owner_hash_raw, sao.script_hash AS stake_address_owner_script_hash,
                  sar.view AS stake_address_rewards_view, sar.hash_raw AS stake_address_rewards_hash_raw, sar.script_hash AS stake_address_rewards_script_hash,
                  sro.cert_index AS stake_registration_owner_cert_index, sro.epoch_no AS stake_registration_owner_epoch_no, sro.tx_id AS stake_registration_owner_tx_id,
                  srr.cert_index AS stake_registration_rewards_cert_index, srr.epoch_no AS stake_registration_rewards_epoch_no, srr.tx_id AS stake_registration_rewards_tx_id
                FROM pool_update AS pu
                  LEFT JOIN stake_address AS sar ON pu.reward_addr_id = sar.id
                  LEFT JOIN stake_registration AS srr ON pu.reward_addr_id = srr.addr_id
                  LEFT JOIN pool_relay AS pr ON pu.id = pr.update_id
                  LEFT JOIN pool_hash AS ph ON pu.hash_id = ph.id
                  LEFT JOIN pool_owner AS po ON pu.id = po.pool_update_id
                  LEFT JOIN stake_address AS sao ON po.addr_id = sao.id
                  LEFT JOIN stake_registration AS sro ON po.addr_id = sro.addr_id
                  LEFT JOIN pool_metadata_ref AS pmr ON pu.meta_id = pmr.id
                  LEFT JOIN pool_retire AS prt ON pu.hash_id = prt.hash_id
                  WHERE ph.view = $1
                  ORDER BY pu.id DESC;

              -- Show pool networking information as of the most recent active epoch update; this includes retired pools
              PREPARE show_pools_network_info AS
                WITH
                  recent_active AS (SELECT hash_id, MAX (active_epoch_no) FROM pool_update
                    WHERE registered_tx_id IN (SELECT MAX(registered_tx_id) FROM pool_update GROUP BY hash_id)
                    AND NOT EXISTS (
                      SELECT * FROM pool_retire
                        WHERE pool_retire.hash_id = pool_update.hash_id
                        AND pool_retire.retiring_epoch <= (SELECT MAX (epoch_no) FROM block)
                    ) GROUP BY hash_id),
                  recent_info AS (
                    SELECT recent_active.hash_id, MAX (id) FROM pool_update
                      INNER JOIN recent_active ON (pool_update.active_epoch_no = recent_active.max AND pool_update.hash_id = recent_active.hash_id)
                      GROUP BY recent_active.hash_id
                  )
                SELECT pool_hash.view, active_epoch_no, ticker_name, ipv4, ipv6, dns_name, port FROM recent_info
                  INNER JOIN pool_update ON recent_info.max = pool_update.id
                  INNER JOIN pool_hash ON pool_hash.id = pool_update.hash_id
                  INNER JOIN pool_relay ON pool_relay.update_id = recent_info.max
                  LEFT JOIN pool_offline_data ON pool_offline_data.pmr_id = pool_update.meta_id
                  ORDER BY pool_hash.view;

              -- Show the pool stake distribution by epoch
              PREPARE show_pool_stake_dist_fn (word31type) AS
                SELECT pool_hash.view, SUM (amount) AS lovelace FROM epoch_stake
                  INNER JOIN pool_hash ON epoch_stake.pool_id = pool_hash.id
                  WHERE epoch_no = $1 GROUP BY pool_hash.id ORDER BY view;

              -- Show registered pools as of the current epoch
              PREPARE show_registered_pools AS
                SELECT pool_update.id, hash_id, pool_hash.view, cert_index, pledge, active_epoch_no, meta_id, margin, fixed_cost, registered_tx_id, reward_addr_id FROM pool_update
                  INNER JOIN pool_hash ON pool_update.hash_id = pool_hash.id
                  WHERE registered_tx_id IN (SELECT MAX (registered_tx_id) FROM pool_update GROUP BY hash_id)
                  AND NOT EXISTS (
                    SELECT * FROM pool_retire
                      WHERE pool_retire.hash_id = pool_update.hash_id
                      AND pool_retire.retiring_epoch <= (SELECT MAX (epoch_no) FROM block)
                  );

              -- Show stake address delegation history
              PREPARE show_stake_addr_deleg_history_fn (varchar) AS
                SELECT delegation.active_epoch_no, pool_hash.view FROM delegation
                  INNER JOIN stake_address ON delegation.addr_id = stake_address.id
                  INNER JOIN pool_hash ON delegation.pool_hash_id = pool_hash.id
                  WHERE stake_address.view = $1
                  ORDER BY active_epoch_no ASC;

              -- Show the stake address from a transaction paid with a payment+stake address
              PREPARE show_stake_addr_from_payment_addr_fn (varchar) AS
                SELECT stake_address.id AS stake_address_id, tx_out.tx_id, tx_out.address, stake_address.view AS stake_address FROM tx_out
                  INNER JOIN stake_address ON tx_out.stake_address_id = stake_address.id
                  WHERE address = $1;

              -- Show the stake address rewards history
              PREPARE show_stake_addr_rewards_history_fn (varchar) AS
                SELECT reward.earned_epoch, pool_hash.view AS delegated_pool, reward.amount AS lovelace FROM reward
                  INNER JOIN stake_address ON reward.addr_id = stake_address.id
                  INNER JOIN pool_hash ON reward.pool_id = pool_hash.id
                  WHERE stake_address.view = $1
                  ORDER BY earned_epoch DESC;

              -- Show the percentage of sync completion
              PREPARE show_sync_percent AS
                SELECT 100 * (EXTRACT (epoch FROM (MAX (time) AT TIME ZONE 'UTC')) - EXTRACT (epoch FROM (MIN (time) AT TIME ZONE 'UTC')))
                  / (EXTRACT (epoch FROM (now () AT TIME ZONE 'UTC')) - EXTRACT (epoch FROM (MIN (time) AT TIME ZONE 'UTC')))
                  AS sync_percent FROM block;
            END IF;
          END IF;
        END$$;

        \echo '\nWelcome:\n'
        \echo '  To see an auto-completion list of cardano specific set variables, enter: `:show_<tab><tab>`'
        \echo '  To see an auto-completion list of cardano specific prepared statements, enter: `execute show_<tab><tab>`'
        \echo '  To execute a cardano specific set variable, enter its name, starting with a colon'
        \echo '  To execute a prepared statement: `execute <NAME> (ARG1, ...);` (omit the args list if none)'
        \echo
        \echo 'Note: prepared statements will only become available after cardano-db-sync completes the initial synchronization'
        \echo '\n'
      '';

      cfg = config.services.cardano-postgres;
    in {
      options = {
        services.cardano-postgres = {
          dataDir = mkOption {
            type = nullOr str;
            default = null;
            description = "The directory for postgresql data.  If null, this parameter is not configured.";
          };

          enablePsqlrc = mkOption {
            type = bool;
            default = false;
            description = "Whether to enable a dbsync specific psqlrc file at cfg.psqlrcPath.";
          };

          maxConnections = mkOption {
            type = ints.between 20 9999;
            default = 200;
            description = "The postgresql maximum number of connections to allow, between 20 and 9999";
          };

          psqlrc = mkOption {
            type = str;
            default = psqlrc;
            description = "The psqlrc text.";
          };

          psqlrcPath = mkOption {
            type = str;
            default = "${config.services.postgresql.dataDir}/psqlrc";
            description = "The psqlrc target path.";
          };

          ramAvailableMiB = mkOption {
            type = oneOf [ints.positive float];
            default = memMiB * 0.70;
            description = "The default RAM available for postgresql on the machine in MiB.";
          };

          socketPath = mkOption {
            type = str;
            default = "/run/postgresql";
            description = "The postgresql socket path to use, typically `/run/postgresql`.";
          };

          withPgStatStatements = mkOption {
            type = bool;
            default = true;
            description = ''
              Configure pg_stat_statements which allow performance tracking of queries.
              During non-IO bound runtime, this may impact performance up to ~10%.
            '';
          };
        };
      };

      config = {
        environment.variables.PSQLRC = mkIf cfg.enablePsqlrc cfg.psqlrcPath;
        systemd.services.postgresql.preStart = mkIf cfg.enablePsqlrc (mkAfter "ln -sfn ${psqlrc} ${cfg.psqlrcPath}");

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
