with
  current_epoch AS (
    select max(epoch_no) as current_epoch from block),

  -- Table for active pool constraint registration debugging
  stake_reg_most_recent AS (
    select distinct on (addr_id) id, addr_id, cert_index, epoch_no, tx_id
    from stake_registration
    order by addr_id, tx_id desc, cert_index desc),

  -- Table for active pool constraint, deregistration
  stake_dereg_most_recent AS (
    select distinct on (addr_id) id, addr_id, cert_index, epoch_no, tx_id
    from stake_deregistration
    order by addr_id, tx_id desc, cert_index desc),

  -- Most recent faucet pool delegations per stake address
  -- This query uses the faucet_stake_addr table which is a custom added static table of: key as faucet_delegation_index, value as stake_address
  -- This query's second column is a function of the first column
  faucet_pool_last_active AS (
    select
      key as index,
      value as stake_addr,
      (select pool_hash.view from delegation
        inner join stake_address on delegation.addr_id = stake_address.id
        inner join pool_hash on delegation.pool_hash_id = pool_hash.id
        inner join stake_reg_most_recent on delegation.addr_id = stake_reg_most_recent.addr_id
        left join stake_dereg_most_recent on delegation.addr_id = stake_dereg_most_recent.addr_id
        where stake_address.view = value
        and (stake_dereg_most_recent.tx_id is null or stake_dereg_most_recent.tx_id < delegation.tx_id)
        order by delegation.tx_id desc limit 1) as view
      from faucet_stake_addr),

  -- Pools actively forging in the current epoch
  active_pools AS (
    select distinct(pool_hash_id), view from block
      inner join slot_leader on slot_leader_id=slot_leader.id
      inner join pool_hash on pool_hash_id=pool_hash.id
      where epoch_no=(select * from current_epoch)
      order by pool_hash_id),

  -- Pools actively forging in the current epoch and Chang ready, by id
  chang_ready_pool_ids AS (
    select pool_hash_id from block
      inner join slot_leader on slot_leader_id=slot_leader.id
      where proto_major=9 and proto_minor=1
      and epoch_no=(select * from current_epoch)),

  -- Pools actively forging in the current epoch and Chang ready, by view
  chang_ready_pool_views AS (
    select view from chang_ready_pool_ids
      inner join pool_hash on chang_ready_pool_ids.pool_hash_id=pool_hash.id),

  -- Pools actively forging in the current epoch and Chang ready, by view
  chang_not_ready_pool_views AS (
    select view from active_pools
      where active_pools.view not in (select * from chang_ready_pool_views)),

  -- Current epoch pool delegation
  pool_deleg AS (
    select pool_hash.view, sum (amount) as lovelace from epoch_stake
      inner join pool_hash on epoch_stake.pool_id = pool_hash.id
      where epoch_no = (select * from current_epoch) group by pool_hash.id),

  -- Current epoch pool delegation, Chang ready
  chang_ready_pool_deleg AS (
    select pool_hash.view, sum (amount) as lovelace from epoch_stake
      inner join pool_hash on epoch_stake.pool_id = pool_hash.id
      where epoch_no = (select * from current_epoch)
      and pool_hash.view in (select * from chang_ready_pool_views) group by pool_hash.id),

  -- Current epoch pool delegation, Chang not ready
  chang_not_ready_pool_deleg AS (
    select pool_hash.view, sum (amount) as lovelace from epoch_stake
      inner join pool_hash on epoch_stake.pool_id = pool_hash.id
      where epoch_no = (select * from current_epoch)
      and pool_hash.view not in (select * from chang_ready_pool_views) group by pool_hash.id),

  -- Faucet pool delegations, Chang ready
  faucet_pool_chang_ready AS (
    select * from faucet_pool_last_active
      where view in (select * from chang_ready_pool_views)),

  -- Faucet pool delegations, not Chang ready
  faucet_pool_not_chang_ready AS (
    select * from faucet_pool_last_active
      where view not in (select * from chang_ready_pool_views)),

  summary AS (
    select
      (select count(distinct(pool_hash_id)) from active_pools) as active_pools,
      (select count(view) from faucet_pool_last_active) as total_faucet_delegated_pools,
      (select count(view) from faucet_pool_chang_ready) as faucet_pool_chang_ready,
      (select count(view) from faucet_pool_not_chang_ready) as faucet_pool_not_chang_ready,
      (select sum(lovelace) from pool_deleg) as pool_deleg,
      (select sum(lovelace) from chang_ready_pool_deleg) as chang_ready_pool_deleg,
      (select sum(lovelace) from chang_not_ready_pool_deleg) as chang_not_ready_pool_deleg
  )

  select * from faucet_pool_not_chang_ready;
  -- select * from summary;
  -- select * from chang_ready_pool_deleg;
  -- select * from chang_not_ready_pool_views;
