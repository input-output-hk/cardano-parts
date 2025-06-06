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
    cardano-cli latest query proposals --testnet-magic "$TESTNET_MAGIC" --all-proposals \
      | jq -r 'map(select(.proposalProcedure.govAction.tag == "ParameterChange")) | .[0].actionId.txId'
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
    cardano-cli latest query proposals --testnet-magic "$TESTNET_MAGIC" --all-proposals \
      | jq -r 'map(select(.proposalProcedure.govAction.tag == "HardForkInitiation")) | .[0].actionId.txId'
  )
  DECISION=yes \
    ROLE=cc \
    VOTE_KEY="$CC_DIR/cc-1-hot \
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

  export ENV=custom
  export GENESIS_DIR=state-demo-ng
  export BULK_CREDS=state-demo-ng/bulk.creds.all.json
  export CC_DIR=state-demo-ng/envs/custom/cc-keys
  export DATA_DIR=state-demo-ng/rundir
  export KEY_DIR=state-demo-ng/envs/custom
  export PAYMENT_KEY=state-demo-ng/envs/custom/utxo-keys/rich-utxo
  export STAKE_POOL_DIR=state-demo-ng/groups/stake-pools
  export CARDANO_NODE_SOCKET_PATH="$STATEDIR/node-demo.socket"
  export START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds")

  export NUM_CC_KEYS="${NUM_CC_KEYS:-1}"
  export NUM_GENESIS_KEYS="${NUM_GENESIS_KEYS:-3}"
  export TESTNET_MAGIC="${TESTNET_MAGIC:-42}"
  export POOL_MARGIN="${POOL_MARGIN:-"0.5"}"
  export POOL_NAMES="${POOL_NAMES:-"sp-1 sp-2 sp-3"}"
  export UNSTABLE="${UNSTABLE:-true}"
  export UNSTABLE_LIB="${UNSTABLE_LIB:-true}"
  export USE_ENCRYPTION="${USE_ENCRYPTION:-true}"
  export USE_DECRYPTION="${USE_DECRYPTION:-true}"
  export USE_NODE_CONFIG_BP="${USE_NODE_CONFIG_BP:-false}"
  export DEBUG="${DEBUG:-true}"
  export RETIRE_BOOTSTRAP_POOL="${RETIRE_BOOTSTRAP_POOL:-true}"
  export SECURITY_PARAM="${SECURITY_PARAM:-8}"
  export SLOT_LENGTH="${SLOT_LENGTH:-100}"
  export FIXED_DELAY_SECS="${FIXED_DELAY_SECS:-10}"

  export ERA_CMD=conway

  nix run .#job-gen-custom-node-config-data-ng

  nix run .#job-create-stake-pool-keys

  if [ "$USE_DECRYPTION" = true ]; then
    BOOTSTRAP_CREDS=$(just sops-decrypt-binary "$KEY_DIR"/bootstrap-pool/bulk.creds.bootstrap.json)
    POOL_CREDS=$(just sops-decrypt-binary "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json)
  else
    BOOTSTRAP_CREDS=$(cat "$KEY_DIR"/bootstrap-pool/bulk.creds.bootstrap.json)
    POOL_CREDS=$(cat "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json)
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
  echo "Sleeping 10 seconds until $(date -d  @$(($(date +%s) + 10)))"
  sleep 10
  echo

  echo "Delegating rewards stake key..."
  nix run .#job-delegate-rewards-stake-key
  echo "Sleeping 10 seconds until $(date -d  @$(($(date +%s) + 10)))"
  sleep 10
  echo

  if [ "$RETIRE_BOOTSTRAP_POOL" = "true" ]; then
    echo "Retiring the bootstrap pool..."
    BOOTSTRAP_POOL_DIR="$KEY_DIR/bootstrap-pool" \
      RICH_KEY="$KEY_DIR/utxo-keys/rich-utxo" \
      nix run .#job-retire-bootstrap-pool
    echo "Sleeping 10 seconds until $(date -d  @$(($(date +%s) + 10)))"
    sleep 10
    echo
  else
    echo "Skipping bootstrap pool retirement..."
    echo
  fi

  WAIT_FOR_TIP() {
    TYPE="$1"
    TARGET="$2"
    EPOCH="$1"

    while true; do
        [ "$(jq -re ".$TYPE" <<< "$(just query-tip demo "$TESTNET_MAGIC")")" = "$TARGET" ] && break;
      sleep 2
    done
  }

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
  echo "Sleeping until cost model can be voted on, epoch 1"
  WAIT_FOR_TIP "epoch" "1"
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
    cardano-cli latest query proposals --testnet-magic "$TESTNET_MAGIC" --all-proposals \
      | jq -r 'map(select(.proposalProcedure.govAction.tag == "ParameterChange")) | .[0].actionId.txId'
  ) \
    DECISION=yes \
    ROLE=cc \
    VOTE_KEY="$CC_DIR/cc-1-hot" \
    nix run .#job-submit-vote
  echo "Sleeping until plomin HF can be voted on, epoch 2"
  WAIT_FOR_TIP "epoch" "2"
  echo

  echo "Submitting the CC vote for the Plomin hard fork..."
  export ACTION_TX_ID=$(
    cardano-cli latest query proposals --testnet-magic "$TESTNET_MAGIC" --all-proposals \
      | jq -r 'map(select(.proposalProcedure.govAction.tag == "HardForkInitiation")) | .[0].actionId.txId'
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
  CURRENT_EPOCH=$(jq -re ".epoch" <<< "$(just query-tip demo "$TESTNET_MAGIC")")
  echo "Sleeping until epoch $((CURRENT_EPOCH + 1)) for the plomin HF votes to register..."
  WAIT_FOR_TIP "epoch" "$((CURRENT_EPOCH + 1))"
  echo

  echo "Sleeping until epoch $((CURRENT_EPOCH + 2)) for the Plomin HF action to ratify..."
  WAIT_FOR_TIP "epoch" "$((CURRENT_EPOCH + 2))"
  echo

  just query-tip demo "$TESTNET_MAGIC"
  echo
  echo "Finished sequence..."
  echo "Note that any further gov actions will require a constitution to be adopted."
  echo
