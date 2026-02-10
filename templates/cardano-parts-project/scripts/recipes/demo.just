# Demo specific recipes split out to make diffing and patching the main repo
# Justfile easier as not all repos may utilize these.

# Start a fork to plomin demo
start-demo:
  #!/usr/bin/env bash
  set -euo pipefail
  just stop-node demo

  {{stateDir}}

  echo "Cleaning state-demo..."
  if [ -d state-demo ]; then
    chmod -R +w state-demo
    rm -rf state-demo
  fi

  echo "Generating state-demo config..."

  export ENV=custom
  export GENESIS_DIR=state-demo
  export BULK_CREDS=state-demo/bulk.creds.all.json
  export CC_DIR=state-demo/envs/custom/cc-keys
  export DATA_DIR=state-demo/rundir
  export KEY_DIR=state-demo/envs/custom
  export PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo
  export STAKE_POOL_DIR=state-demo/groups/stake-pools
  export CARDANO_NODE_SOCKET_PATH="$STATEDIR/node-demo.socket"
  export START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds")

  export NUM_CC_KEYS="${NUM_CC_KEYS:-1}"
  export NUM_GENESIS_KEYS="${NUM_GENESIS_KEYS:-3}"
  export TESTNET_MAGIC="${TESTNET_MAGIC:-42}"
  export POOL_MARGIN="${POOL_MARGIN:-"0.5"}"
  export POOL_NAMES="${POOL_NAMES:-"sp-1 sp-2 sp-3"}"
  export UNSTABLE="${UNSTABLE:-true}"
  export UNSTABLE_LIB="${UNSTABLE_LIB:-true}"
  export USE_CREATE_TESTNET_DATA="${USE_CREATE_TESTNET_DATA:-true}"
  export USE_ENCRYPTION="${USE_ENCRYPTION:-true}"
  export USE_DECRYPTION="${USE_DECRYPTION:-true}"
  export USE_NODE_CONFIG_BP="${USE_NODE_CONFIG_BP:-false}"
  export DEBUG="${DEBUG:-true}"
  export SECURITY_PARAM="${SECURITY_PARAM:-8}"
  export SLOT_LENGTH="${SLOT_LENGTH:-100}"
  export FIXED_DELAY_SECS="${FIXED_DELAY_SECS:-10}"

  if [ "$USE_CREATE_TESTNET_DATA" = true ]; then
    ERA_CMD="conway" \
      nix run .#job-gen-custom-node-config-data
  else
    for i in "$(seq 1 "$NUM_CC_KEYS")"; do
      INDEX="$i" \
        nix run .#job-gen-keys-cc
    done

    ERA_CMD="alonzo" \
      nix run .#job-gen-custom-node-config
  fi

  ERA_CMD="alonzo" \
    nix run .#job-create-stake-pool-keys

  if [ "$USE_DECRYPTION" = true ]; then
    BFT_CREDS=$(just sops-decrypt-binary "$KEY_DIR"/delegate-keys/bulk.creds.bft.json)
    POOL_CREDS=$(just sops-decrypt-binary "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json)
  else
    BFT_CREDS=$(cat "$KEY_DIR"/delegate-keys/bulk.creds.bft.json)
    POOL_CREDS=$(cat "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json)
  fi
  (
    jq -r '.[]' <<< "$BFT_CREDS"
    jq -r '.[]' <<< "$POOL_CREDS"
  ) | jq -s > "$BULK_CREDS"

  echo "Start cardano-node in the background. Run \"just stop-node demo\" to stop"
  NODE_CONFIG="$DATA_DIR/node-config.json" \
    NODE_TOPOLOGY="$DATA_DIR/topology.json" \
    SOCKET_PATH="$STATEDIR/node-demo.socket" \
    nohup setsid nix run .#run-cardano-node &> "$STATEDIR/node-demo.log" & echo $! > "$STATEDIR/node-demo.pid" &
  just set-default-cardano-env demo "$TESTNET_MAGIC" "$PPID"
  echo "Sleeping 30 seconds until $(date -d  @$(($(date +%s) + 30)))"
  sleep 30
  echo

  if [ "$USE_CREATE_TESTNET_DATA" = false ]; then
    echo "Moving genesis utxo in epoch 0..."
    BYRON_SIGNING_KEY="$KEY_DIR"/utxo-keys/shelley.000.skey \
      ERA_CMD="alonzo" \
      nix run .#job-move-genesis-utxo
    echo "Sleeping 10 seconds until $(date -d  @$(($(date +%s) + 10)))"
    sleep 10
    echo
  fi

  echo "Registering stake pools in epoch 0..."
  POOL_RELAY=demo.local \
    POOL_RELAY_PORT=3001 \
    ERA_CMD="alonzo" \
    nix run .#job-register-stake-pools
  echo "Sleeping $FIXED_DELAY_SECS seconds until $(date -d  @$(($(date +%s) + $FIXED_DELAY_SECS)))"
  sleep "$FIXED_DELAY_SECS"
  echo

  WAIT_FOR_TIP() {
    TYPE="$1"
    TARGET="$2"
    EPOCH="$1"

    while true; do
        [ "$(jq -re ".$TYPE" <<< "$(just query-tip demo "$TESTNET_MAGIC")")" = "$TARGET" ] && break;
      sleep 2
    done
  }

  echo "Delegating rewards stake key in epoch 0..."
  ERA_CMD="alonzo" \
    nix run .#job-delegate-rewards-stake-key
  echo "Sleeping until epoch 1"
  WAIT_FOR_TIP "epoch" "1"
  echo

  echo "Forking to babbage in epoch 1..."
  just query-tip demo "$TESTNET_MAGIC"
  MAJOR_VERSION=7 \
    ERA_CMD="alonzo" \
    nix run .#job-update-proposal-hard-fork
  echo "Sleeping until babbage, epoch 2"
  WAIT_FOR_TIP "era" "Babbage"
  echo

  echo "Forking to babbage (intra-era) in epoch 2..."
  just query-tip demo "$TESTNET_MAGIC"
  MAJOR_VERSION=8 \
    ERA_CMD="babbage" \
    nix run .#job-update-proposal-hard-fork
  echo "Sleeping until epoch babbage (intra-era), epoch 3"
  WAIT_FOR_TIP "epoch" "3"
  echo

  echo "Forking to conway in epoch 3..."
  just query-tip demo "$TESTNET_MAGIC"
  MAJOR_VERSION=9 \
    ERA_CMD="babbage" \
    nix run .#job-update-proposal-hard-fork
  echo "Sleeping until conway, epoch 4"
  WAIT_FOR_TIP "era" "Conway"
  echo

  echo "Authorizing the CC member's hot credentials..."
  INDEX=1 \
    nix run .#job-register-cc
  echo "Sleeping $FIXED_DELAY_SECS seconds until $(date -d  @$(($(date +%s) + $FIXED_DELAY_SECS)))"
  sleep "$FIXED_DELAY_SECS"
  echo

  # If both cost model and plomin HF are submitted in the same epoch and
  # ratified in the same epoch, cost model may fail to enact.
  echo "Submitting a Plomin prep cost model action..."
  PROPOSAL_ARGS=("--cost-model-file" "scripts/cost-models/mainnet-plutusv3-pv10-prep.json")
  ACTION="create-protocol-parameters-update" \
    STAKE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f1 -d' ' <<< "$POOL_NAMES")-owner-stake" \
    nix run .#job-submit-gov-action -- "${PROPOSAL_ARGS[@]}"
  echo "Sleeping $FIXED_DELAY_SECS seconds until $(date -d  @$(($(date +%s) + $FIXED_DELAY_SECS)))"
  echo "Sleeping until cost model can be voted on, epoch 5"
  WAIT_FOR_TIP "epoch" "5"
  echo

  echo "Submitting a Plomin hard fork action..."
  PROPOSAL_ARGS=("--protocol-major-version" "10" "--protocol-minor-version" "0")
  ACTION="create-hardfork" \
    STAKE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f1 -d' ' <<< "$POOL_NAMES")-owner-stake" \
    nix run .#job-submit-gov-action -- "${PROPOSAL_ARGS[@]}"
  echo "Sleeping $FIXED_DELAY_SECS seconds until $(date -d  @$(($(date +%s) + $FIXED_DELAY_SECS)))"
  sleep "$FIXED_DELAY_SECS"
  echo

  # Only the CC member needs to approve the cost model, but CC and SPOs need to approve the HF
  echo "Submitting the CC vote for cost model..."
  ACTION_TX_ID=$(
    cardano-cli latest query gov-state --testnet-magic "$TESTNET_MAGIC" \
      | jq -r '.proposals | map(select(.proposalProcedure.govAction.tag == "ParameterChange")) | .[0].actionId.txId'
  ) \
    DECISION=yes \
    ROLE=cc \
    VOTE_KEY="$CC_DIR/cc-1-hot" \
    nix run .#job-submit-vote
  echo "Sleeping until plomin HF can be voted on, epoch 6"
  WAIT_FOR_TIP "epoch" "6"
  echo

  echo "Submitting the CC vote for the Plomin hard fork..."
  export ACTION_TX_ID=$(
    cardano-cli latest query gov-state --testnet-magic "$TESTNET_MAGIC" \
      | jq -r '.proposals | map(select(.proposalProcedure.govAction.tag == "HardForkInitiation")) | .[0].actionId.txId'
  )
  DECISION=yes \
    ROLE=cc \
    VOTE_KEY="$CC_DIR/cc-1-hot" \
    nix run .#job-submit-vote
  echo "Sleeping $FIXED_DELAY_SECS seconds until $(date -d  @$(($(date +%s) + $FIXED_DELAY_SECS)))"
  sleep "$FIXED_DELAY_SECS"
  echo

  POOL_NAME_ARR=($POOL_NAMES)
  for i in $(seq 1 "${#POOL_NAME_ARR[@]}"); do
    echo "Submitting the pool $i vote for the Plomin hard fork..."
    DECISION=yes \
      ROLE=spo \
      VOTE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f${i} -d' ' <<< "$POOL_NAMES")-cold" \
      nix run .#job-submit-vote
    echo "Sleeping $FIXED_DELAY_SECS seconds until $(date -d  @$(($(date +%s) + $FIXED_DELAY_SECS)))"
    sleep "$FIXED_DELAY_SECS"
  done
  echo "Sleeping until epoch 7 for the plomin HF votes to register..."
  WAIT_FOR_TIP "epoch" "7"
  echo

  echo "Sleeping until epoch 8 for the Plomin HF action to ratify..."
  WAIT_FOR_TIP "epoch" "8"
  echo

  just query-tip demo "$TESTNET_MAGIC"
  echo
  echo "Finished sequence..."
  echo "Note that any further gov actions will require a constitution to be adopted."
  echo

# Start a fork to plomin demo using create-testnet-data-ng job
start-demo-ng:
  #!/usr/bin/env bash
  set -euo pipefail
  just stop-node demo

  {{stateDir}}

  echo "Cleaning state-demo-ng..."
  if [ -d state-demo-ng ]; then
    chmod -R +w state-demo-ng
    rm -rf state-demo-ng
  fi

  echo "Generating state-demo-ng config..."
  echo "Sourcing bash helper functions..."
  source scripts/bash-fns.sh

  export ENV=custom
  export GENESIS_DIR=state-demo-ng
  export BULK_CREDS=state-demo-ng/bulk.creds.all.json
  export CC_DIR=state-demo-ng/envs/custom/cc-keys
  export DREP_DEPOSIT="500000000"
  export DREP_DIR=state-demo-ng/envs/custom/drep
  export VOTING_POWER="10000000000"
  export DATA_DIR=state-demo-ng/rundir
  export KEY_DIR=state-demo-ng/envs/custom
  export PAYMENT_KEY=state-demo-ng/envs/custom/utxo-keys/rich-utxo
  export STAKE_POOL_DIR=state-demo-ng/groups/stake-pools
  export CARDANO_NODE_SOCKET_PATH="$STATEDIR/node-demo.socket"
  export START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds")

  export NUM_CC_KEYS="${NUM_CC_KEYS:-3}"
  export NUM_GENESIS_KEYS="${NUM_GENESIS_KEYS:-3}"
  export TESTNET_MAGIC="${TESTNET_MAGIC:-42}"
  export POOL_MARGIN="${POOL_MARGIN:-"0.5"}"
  export POOL_NAMES="${POOL_NAMES:-"sp-1 sp-2 sp-3"}"
  export UNSTABLE="${UNSTABLE:-true}"
  export UNSTABLE_LIB="${UNSTABLE_LIB:-true}"
  export USE_ENCRYPTION="${USE_ENCRYPTION:-true}"
  export USE_DECRYPTION="${USE_DECRYPTION:-true}"
  export USE_NODE_CONFIG_BP="${USE_NODE_CONFIG_BP:-false}"
  export USE_FINAL_CONSTITUTION_IN_GENESIS="${USE_FINAL_CONSTITUTION_IN_GENESIS:-true}"
  export DEBUG="${DEBUG:-true}"
  export RETIRE_BOOTSTRAP_POOL="${RETIRE_BOOTSTRAP_POOL:-true}"
  export SECURITY_PARAM="${SECURITY_PARAM:-8}"
  export SLOT_LENGTH="${SLOT_LENGTH:-100}"

  # Use a final constitution copy from mainnet to indicate when we are no longer using an interim constitution.
  export IPFS_GATEWAY_URI="https://ipfs.io"
  export SCRIPT_FILE_URL="https://book.play.dev.cardano.org/environments/preview/guardrails-script.plutus"
  CONSTITUTION_ANCHOR_DATAHASH="2a61e2f4b63442978140c77a70daab3961b22b12b63b13949a390c097214d1c5"
  CONSTITUTION_ANCHOR_URL="ipfs://bafkreiazhhawe7sjwuthcfgl3mmv2swec7sukvclu3oli7qdyz4uhhuvmy"
  CONSTITUTION_SCRIPT="fa24fb305126805cf2164c161d852a0e7330cf988f1fe558cf7d4a64"

  if [ "$USE_FINAL_CONSTITUTION_IN_GENESIS" = "true" ]; then
    export CONSTITUTION_ANCHOR_DATAHASH
    export CONSTITUTION_ANCHOR_URL
    export CONSTITUTION_SCRIPT
    export USE_GUARDRAILS="true"
  fi

  export ERA_CMD=conway

  nix run .#job-gen-custom-node-config-data-ng

  nix run .#job-create-stake-pool-keys

  if [ "$USE_DECRYPTION" = true ]; then
    BOOTSTRAP_CREDS=$(just sops-decrypt-binary "$KEY_DIR"/bootstrap-pool/bulk.creds.bootstrap.json)
    POOL_CREDS=$(just sops-decrypt-binary "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json)

    # Bash helper fns don't have encryption/decryption support, so we set up
    # some vars to enable faucet use in the case the bootstrap pool is not retired.
    RICH_ADDR=$(just sops-decrypt-binary "$PAYMENT_KEY".addr)
    RICH_CONTENT=$(just sops-decrypt-binary "$PAYMENT_KEY".skey)
  else
    BOOTSTRAP_CREDS=$(cat "$KEY_DIR"/bootstrap-pool/bulk.creds.bootstrap.json)
    POOL_CREDS=$(cat "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json)
    RICH_ADDR=$(cat "$PAYMENT_KEY".addr)
    RICH_CONTENT=$(cat "$PAYMENT_KEY".skey)
  fi
  (
    jq -r '.[]' <<< "$BOOTSTRAP_CREDS"
    jq -r '.[]' <<< "$POOL_CREDS"
  ) | jq -s > "$BULK_CREDS"

  echo "Start cardano-node in the background. Run \"just stop-node demo\" to stop"
  NODE_CONFIG="$DATA_DIR/node-config.json" \
    NODE_TOPOLOGY="$DATA_DIR/topology.json" \
    SOCKET_PATH="$STATEDIR/node-demo.socket" \
    nohup setsid nix run .#run-cardano-node &> "$STATEDIR/node-demo.log" & echo $! > "$STATEDIR/node-demo.pid" &
  just set-default-cardano-env demo "$TESTNET_MAGIC" "$PPID"
  echo "Sleeping 30 seconds until $(date -d  @$(($(date +%s) + 30)))"
  sleep 30
  echo

  echo "Registering stake pools..."
  POOL_RELAY=demo-ng.local \
    POOL_RELAY_PORT=3001 \
    nix run .#job-register-stake-pools
  wait-for-mempool
  echo

  echo "Delegating rewards stake key..."
  nix run .#job-delegate-rewards-stake-key
  wait-for-mempool
  echo

  if [ "$RETIRE_BOOTSTRAP_POOL" = "true" ]; then
    echo "Retiring the bootstrap pool..."
    BOOTSTRAP_POOL_DIR="$KEY_DIR/bootstrap-pool" \
      RICH_KEY="$KEY_DIR/utxo-keys/rich-utxo" \
      nix run .#job-retire-bootstrap-pool
    wait-for-mempool
    echo
  else
    echo "Skipping bootstrap pool retirement..."
    echo "Adding an extra UTXO to the rich key address for collateral funding..."
    faucet "$RICH_ADDR" "$RICH_ADDR" <(echo "$RICH_CONTENT") 1000000000
    echo
  fi

  for i in $(seq 1 "$NUM_CC_KEYS"); do
    echo "Authorizing CC$i member's hot credentials..."
    INDEX="$i" \
      nix run .#job-register-cc
    wait-for-mempool
    echo
  done

  echo "Creating and registering drep-0"
  if [ "$USE_DECRYPTION" = true ]; then
    export POOL_DELEG_ID=$(just sops-decrypt-binary "$STAKE_POOL_DIR/no-deploy/sp-1-pool.id")
  else
    export POOL_DELEG_ID=$(cat "$STAKE_POOL_DIR/no-deploy/sp-1-pool.id")
  fi
  INDEX="0" \
    STAKE_DEPOSIT="2000000" \
    VOTING_POWER="10000000000" \
    nix run .#job-register-drep
  wait-for-mempool

  # If the cost model is submitted near the end of the epoch and voted on, it
  # will fail to ratify in the next epoch.
  echo "Sleeping to submit the cost model at the start of the next epoch, epoch 1"
  wait-for-tip "epoch" "1"
  echo

  # If both cost model and Plomin hard fork proposal are submitted in the same
  # epoch, the cost model will fail to take effect and PlutusV2 will be
  # missing.  We'll delay submission of Plutus HF proposal by one epoch to
  # allow for ratification of the cost model first.
  echo "Submitting a Plomin prep cost model action..."
  PROPOSAL_ARGS=("--cost-model-file" "scripts/cost-models/mainnet-plutusv3-pv10-prep.json")
  ACTION="create-protocol-parameters-update" \
    STAKE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f1 -d' ' <<< "$POOL_NAMES")-owner-stake" \
    nix run .#job-submit-gov-action -- "${PROPOSAL_ARGS[@]}"
  wait-for-mempool
  echo

  # Only the CC members need to approve the cost model, but both CCs and SPOs need to approve the HF.
  # Drep votes are disallowed during Conway bootstrapping.
  export ACTION_TX_ID=$(
    cardano-cli latest query gov-state --testnet-magic "$TESTNET_MAGIC" \
      | jq -r '.proposals | map(select(.proposalProcedure.govAction.tag == "ParameterChange")) | .[0].actionId.txId'
  )

  for i in $(seq 1 "$NUM_CC_KEYS"); do
    echo "Submitting the CC$i vote for the cost model..."
      DECISION=yes \
      ROLE=cc \
      VOTE_KEY="$CC_DIR/cc-$i-hot" \
      nix run .#job-submit-vote
    wait-for-mempool
    echo
  done

  echo "Sleeping until the cost model proposal ratifies, epoch 2"
  wait-for-tip "epoch" "2"
  echo

  echo "Submitting a Plomin hard fork action..."
  PROPOSAL_ARGS=("--protocol-major-version" "10" "--protocol-minor-version" "0")
  ACTION="create-hardfork" \
    STAKE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f1 -d' ' <<< "$POOL_NAMES")-owner-stake" \
    nix run .#job-submit-gov-action -- "${PROPOSAL_ARGS[@]}"
  wait-for-mempool
  echo

  export ACTION_TX_ID=$(
    cardano-cli latest query gov-state --testnet-magic "$TESTNET_MAGIC" \
      | jq -r '.proposals | map(select(.proposalProcedure.govAction.tag == "HardForkInitiation")) | .[0].actionId.txId'
  )

  for i in $(seq 1 "$NUM_CC_KEYS"); do
    echo "Submitting the CC$i vote for the Plomin hard fork..."
    DECISION=yes \
      ROLE=cc \
      VOTE_KEY="$CC_DIR/cc-$i-hot" \
      nix run .#job-submit-vote
    wait-for-mempool
    echo
  done

  POOL_NAME_ARR=($POOL_NAMES)
  for i in $(seq 1 "${#POOL_NAME_ARR[@]}"); do
    echo "Submitting the pool $i vote for the Plomin hard fork..."
    DECISION=yes \
      ROLE=spo \
      VOTE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f${i} -d' ' <<< "$POOL_NAMES")-cold" \
      nix run .#job-submit-vote
    wait-for-mempool
  done

  CURRENT_EPOCH=$(jq -re ".epoch" <<< "$(just query-tip demo "$TESTNET_MAGIC")")
  echo "Sleeping until epoch $((CURRENT_EPOCH + 1)) for the Plomin HF votes to ratify..."
  wait-for-tip "epoch" "$((CURRENT_EPOCH + 1))"
  echo

  echo "Sleeping until epoch $((CURRENT_EPOCH + 2)) for the Plomin HF action to enact..."
  wait-for-tip "epoch" "$((CURRENT_EPOCH + 2))"
  echo

  if ! [ "$USE_FINAL_CONSTITUTION_IN_GENESIS" = "true" ]; then
    # Only the CC and Drep members need to approve the new constitution.
    # Drep votes are now required since Conway bootstrap is complete.
    echo "Submitting a new constitution..."
    PROPOSAL_ARGS=(
      "--constitution-url" "$CONSTITUTION_ANCHOR_URL"
      "--constitution-hash" "$CONSTITUTION_ANCHOR_DATAHASH"
      "--constitution-script-hash" "$CONSTITUTION_SCRIPT"
    )
    ACTION="create-constitution" \
      STAKE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f1 -d' ' <<< "$POOL_NAMES")-owner-stake" \
      nix run .#job-submit-gov-action -- "${PROPOSAL_ARGS[@]}"
    wait-for-mempool
    echo

    # To obtain the governance action from proposal query, we would have to wait for the next epoch.
    # Instead, we'll obtain the action id from the txid of the signed transaction body.
    export ACTION_TX_ID=$(
      cardano-cli latest transaction txid --tx-file tx-create-constitution.txsigned | jq -r .txhash
    )

    for i in $(seq 1 "$NUM_CC_KEYS"); do
      echo "Submitting the CC$i vote for the new constitution..."
        DECISION=yes \
        ROLE=cc \
        VOTE_KEY="$CC_DIR/cc-$i-hot" \
        nix run .#job-submit-vote
      wait-for-mempool
      echo
    done

    echo "Submitting the drep-0 vote for the new constitution..."
      DECISION=yes \
      ROLE=drep \
      VOTE_KEY="$DREP_DIR/drep-0" \
      nix run .#job-submit-vote
    wait-for-mempool
    echo

    echo "Sleeping until epoch $((CURRENT_EPOCH + 3)) for the new constitution votes to ratify..."
    wait-for-tip "epoch" "$((CURRENT_EPOCH + 3))"
    echo

    echo "Sleeping until epoch $((CURRENT_EPOCH + 4)) for the new constitution votes to enact..."
    wait-for-tip "epoch" "$((CURRENT_EPOCH + 4))"
    echo
  fi

  echo "Submitting a Dijkstra hard fork action..."
  PREV_GOV_ACTION=$(cardano-cli latest query gov-state --testnet-magic "$TESTNET_MAGIC" | jq -r '.nextRatifyState.nextEnactState.prevGovActionIds.HardFork')
  PREV_GOV_ACTION_TX_ID=$(jq '.txId' <<< "$PREV_GOV_ACTION")
  PREV_GOV_ACTION_INDEX=$(jq '.govActionIx' <<< "$PREV_GOV_ACTION")
  PROPOSAL_ARGS=(
    "--prev-governance-action-tx-id" "$PREV_GOV_ACTION_TX_ID"
    "--prev-governance-action-index" "$PREV_GOV_ACTION_INDEX"
    "--protocol-major-version" "11"
    "--protocol-minor-version" "0"
  )
  ACTION="create-hardfork" \
    STAKE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f1 -d' ' <<< "$POOL_NAMES")-owner-stake" \
    nix run .#job-submit-gov-action -- "${PROPOSAL_ARGS[@]}"
  wait-for-mempool
  echo

  export ACTION_TX_ID=$(
    cardano-cli latest query gov-state --testnet-magic "$TESTNET_MAGIC" \
      | jq -r '.proposals | map(select(.proposalProcedure.govAction.tag == "HardForkInitiation")) | .[0].actionId.txId'
  )

  for i in $(seq 1 "$NUM_CC_KEYS"); do
    echo "Submitting the CC$i vote for the Dijkstra hard fork..."
    DECISION=yes \
      ROLE=cc \
      VOTE_KEY="$CC_DIR/cc-$i-hot" \
      nix run .#job-submit-vote
    wait-for-mempool
    echo
  done

  POOL_NAME_ARR=($POOL_NAMES)
  for i in $(seq 1 "${#POOL_NAME_ARR[@]}"); do
    echo "Submitting the pool $i vote for the Dijkstra hard fork..."
    DECISION=yes \
      ROLE=spo \
      VOTE_KEY="$STAKE_POOL_DIR/no-deploy/$(cut -f${i} -d' ' <<< "$POOL_NAMES")-cold" \
      nix run .#job-submit-vote
    wait-for-mempool
  done

  echo "Submitting the drep-0 vote for the Dijkstra hard fork..."
    DECISION=yes \
    ROLE=drep \
    VOTE_KEY="$DREP_DIR/drep-0" \
    nix run .#job-submit-vote
  wait-for-mempool
  echo

  CURRENT_EPOCH=$(jq -re ".epoch" <<< "$(just query-tip demo "$TESTNET_MAGIC")")
  echo "Sleeping until epoch $((CURRENT_EPOCH + 1)) for the Dijkstra hard fork to ratify..."
  wait-for-tip "epoch" "$((CURRENT_EPOCH + 1))"
  echo

  echo "Sleeping until epoch $((CURRENT_EPOCH + 2)) for the Dijkstra hard fork to enact..."
  wait-for-tip "epoch" "$((CURRENT_EPOCH + 2))"
  echo

  just query-tip demo "$TESTNET_MAGIC"
  echo
  echo "Finished sequence..."
  echo
