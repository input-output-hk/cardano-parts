# shellcheck disable=SC2148
#
# Various bash helper fns which aren't used enough to move to just recipes.

# A handy transaction submission function with mempool monitoring.
# CARDANO_NODE_{NETWORK_ID,SOCKET_PATH}, TESTNET_MAGIC should already be exported.
submit() (
  set -euo pipefail
  TX_SIGNED="$1"

  TXID=$(cardano-cli latest transaction txid --tx-file "$TX_SIGNED" | jq -re .txhash)

  echo "Submitting $TX_SIGNED with txid $TXID..."
  cardano-cli latest transaction submit --tx-file "$TX_SIGNED"

  EXISTS="true"
  while [ "$EXISTS" = "true" ]; do
    EXISTS=$(cardano-cli latest query tx-mempool tx-exists "$TXID" | jq -re .exists || true)
    if [ "$EXISTS" = "true" ]; then
      echo "The transaction still exists in the mempool, sleeping 5s: $TXID"
    else
      echo "The transaction has been removed from the mempool."
    fi
    sleep 5
  done
  echo "Transaction $TX_SIGNED with txid $TXID submitted successfully."
  echo
)

foreach-pair() (
  set -euo pipefail

  [ -n "${DEBUG:-}" ] && set -x

  if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  foreach-pair \$STRING_LIST_1 \$STRING_LIST_2 \$STRING_CMD"
    echo
    echo "Where:"
    echo "  \$STRING_CMD has \$i and \$j embedded as iters from the two lists"
    echo
    echo "Example:"
    echo "  foreach-pair \"\$(just ssh-list name "preview1.*")\" \"\$(just ssh-list region "preview1.*")\" 'just aws-ec2-status \$i \$j'"
    exit 1
  fi

  local l1="$1"
  local l2="$2"
  local cmd="$3"

  read -r -a l1 <<< "$l1"
  read -r -a l2 <<< "$l2"

  if [[ ${#l1[@]} -ne ${#l2[@]} ]]; then
    echo "Error: Lists are not the same length." >&2
    exit 1
  fi

  local length=${#l1[@]}

  for ((n = 0; n < length; n++)); do
    # shellcheck disable=SC2034
    local i="${l1[n]}"
    # shellcheck disable=SC2034
    local j="${l2[n]}"

    eval "$cmd" || true
  done
)

return-utxo() (
  set -euo pipefail

  [ -n "${DEBUG:-}" ] && set -x
  SIGNING_TX_ARGS=()

  if [ "$#" -ne 4 ] && [ "$#" -ne 5 ]; then
    # shellcheck disable=SC2016
    echo "$0"' $ENV $SEND_ADDR $UTXO $PAYMENT_SKEY [$STAKE_SKEY]'
    echo
    echo "  ENV          -- The environment to be used"
    echo "  SEND_ADDR    -- The send to address"
    echo "  UTXO         -- The UTXO including index in \$UTXO#IDX format"
    echo "  PAYMENT_SKEY -- The path to the payment secret key"
    echo "  [STAKE_SKEY] -- The path to the stake secret key [Optional]"
    exit 1
  else
    # Read file contents rather than saving the path in case it is a streamed
    # file input redirection from a decryption output.
    ENV="$1"
    SEND_ADDR="$2"
    UTXO="$3"
    PAYMENT_SKEY=$(< "$4")
    if [ "$#" -eq 5 ]; then
      STAKE_SKEY=$(< "$5")
    fi
  fi

  just set-default-cardano-env "$ENV"
  echo

  PROMPT() {
    echo
    read -p "Does this look correct [yY]? " -n 1 -r
    echo
    if ! [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborting the fund transfer."
      exit 1
    fi
    echo
  }

  TS=$(date -u +%y-%m-%d_%H-%M-%S)
  BASENAME="tx-fund-transfer-$ENV-$TS"

  PAYMENT_VKEY=$(cardano-cli latest key verification-key --signing-key-file <(echo -n "$PAYMENT_SKEY") --verification-key-file /dev/stdout)

  if [ "$#" -eq 5 ]; then
    STAKE_VKEY=$(cardano-cli latest key verification-key --signing-key-file <(echo -n "$STAKE_SKEY") --verification-key-file /dev/stdout)

    SIGNING_TX_ARGS+=(
      "--signing-key-file" "<(echo -n \"\$STAKE_SKEY\")"
    )
  fi

  SOURCE_ADDR=$(
    if [ "$#" -eq 4 ]; then
      cardano-cli latest address build \
        --payment-verification-key-file <(echo -n "$PAYMENT_VKEY") 2> /dev/null
    else
      cardano-cli latest address build \
        --payment-verification-key-file <(echo -n "$PAYMENT_VKEY") \
        --stake-verification-key-file <(echo -n "$STAKE_VKEY") 2> /dev/null \
      || { \
        STAKE_VKEY_FROM_EXT=$(cardano-cli latest key non-extended-key --extended-verification-key-file <(echo -n "$STAKE_VKEY") --verification-key-file /dev/stdout)

        cardano-cli latest address build \
          --payment-verification-key-file <(echo -n "$PAYMENT_VKEY") \
          --stake-verification-key-file <(echo -n "$STAKE_VKEY_FROM_EXT")
        }
    fi
  )

  echo "For environment $ENV, the source address of $SOURCE_ADDR contains the following lovelace only UTxOs:"
  cardano-cli latest query utxo --address "$SOURCE_ADDR" | jq 'to_entries | map(select(.value.value | length == 1)) | sort_by(.value.value.lovelace) | from_entries'
  PROMPT

  echo "For environment $ENV, the send to address of $SEND_ADDR contains the following lovelace only UTxOs:"
  cardano-cli latest query utxo --address "$SEND_ADDR" | jq 'to_entries | map(select(.value.value | length == 1)) | sort_by(.value.value.lovelace) | from_entries'
  PROMPT

  echo "The provided UTXO has an ID and value of:"
  SELECTED_UTXO=$(
    cardano-cli latest query utxo \
      --address "$SOURCE_ADDR" \
      --testnet-magic "$TESTNET_MAGIC" \
    | jq -e -r --arg selectedUtxo "$UTXO" 'to_entries[]
      |
        select(.key == $selectedUtxo)
          | {"txin": .key, "address": .value.address, "amount": .value.value.lovelace}'
  )

  TXIN=$(jq -r .txin <<< "$SELECTED_UTXO")
  TXIN_VALUE=$(jq -r .amount <<< "$SELECTED_UTXO")
  echo "  UTXO: $TXIN"
  echo "  Value: $TXIN_VALUE"
  echo
  echo "Assembling transaction with details of:"
  echo "  Send to address: $SEND_ADDR"
  echo "  From address: $SOURCE_ADDR"
  echo "  Send amount: $TXIN_VALUE lovelace"
  echo "  Fee amount: 0.2 ADA"
  echo "  Funding UTxO: $TXIN"
  echo "  Funding UTxO value: $TXIN_VALUE lovelace"
  PROMPT

  cardano-cli latest transaction build-raw \
    --tx-in "$TXIN" \
    --tx-out "$SEND_ADDR+$((TXIN_VALUE - 200000))" \
    --fee 200000 \
    --out-file "$BASENAME.raw"

  # shellcheck disable=2116
  SIGNING_CMD=$(echo "cardano-cli latest transaction sign \
    --tx-body-file \"\$BASENAME.raw\" \
    --signing-key-file <(echo -n \"\$PAYMENT_SKEY\") \
    ${SIGNING_TX_ARGS[*]} \
    --testnet-magic \"\$TESTNET_MAGIC\" \
    --out-file \$BASENAME.signed"
  )
  eval "$SIGNING_CMD"

  echo
  echo "The transaction has been prepared and signed:"
  cardano-cli debug transaction view --tx-file "$BASENAME.signed"
  echo
  echo "If you answer affirmative to the next prompt this transaction will be submitted to the network!"
  PROMPT

  submit "$BASENAME.signed"
)

# A handy faucet submission function with mempool monitoring, usable on custom networks.
# CARDANO_NODE_{NETWORK_ID,SOCKET_PATH}, TESTNET_MAGIC should already be exported.
faucet() (
  SEND_ADDR="$1"
  RICH_ADDR="$2"
  RICH_SKEY_PATH="$3"
  LOVELACE="$4"

  UTXOS=$(cardano-cli query utxo --address "$RICH_ADDR")
  UTXO=$(jq -r 'to_entries | max_by(.value.value.lovelace) | { (.key): .value }' <<< "$UTXOS")
  UTXO_TX=$(jq -r 'keys[0]' <<< "$UTXO")

  cardano-cli latest transaction build \
    --tx-in "$UTXO_TX" \
    --tx-out "$SEND_ADDR+$LOVELACE" \
    --change-address "$RICH_ADDR" \
    --testnet-magic "$TESTNET_MAGIC" \
    --out-file faucet.txbody

  cardano-cli latest transaction sign \
    --tx-body-file faucet.txbody \
    --signing-key-file "$RICH_SKEY_PATH" \
    --testnet-magic "$TESTNET_MAGIC" \
    --out-file faucet.txsigned

  submit faucet.txsigned
)

run-node-faketime() (
  if [ "${UNSTABLE:-}" = "true" ]; then
    CMD="cardano-node-ng"
  else
    CMD="cardano-node"
  fi

  # If an older glibc is needed, obtain it from the correct nixpkgs:
  # nix run github:nixos/nixpkgs/nixos-23.05#libfaketime -- "$1" "$CMD" run \
  faketime "$1" "$CMD" run \
    --config "$DATA_DIR"/node-config.json \
    --database-path "$DATA_DIR"/db \
    --topology "$DATA_DIR"/topology.json \
    +RTS -N2 -A16m -qg -qb -M3584M -RTS \
    --socket-path "$DATA_DIR"/node.socket \
    --host-addr 0.0.0.0 \
    --port 3001 \
    --bulk-credentials-file "$GENESIS_DIR"/bulk.creds.all.json \
    | tee -a "$DATA_DIR"/node.log
)

synth-prep() (
  echo "Prepping for block synthesis..."
  cp "$DATA_DIR"/db/protocolMagicId "$DATA_DIR"/
  rm "$DATA_DIR"/db/{clean,gsm,lock,protocolMagicId} -rf
)

synth-restore() (
  cp "$DATA_DIR"/protocolMagicId "$DATA_DIR"/db/
  echo "Synthesis clean up complete."
)

synth-slots() (
  if [ "${UNSTABLE:-}" = "true" ]; then
    CMD="db-synthesizer-ng"
  else
    CMD="db-synthesizer"
  fi

  synth-prep
  "$CMD" \
    --config "$DATA_DIR"/node-config.json \
    --db "$DATA_DIR"/db \
    --bulk-credentials-file "$GENESIS_DIR/bulk.creds.all.json" \
    -a \
    -s "$1"
  synth-restore
)

synth-epochs() (
  if [ "${UNSTABLE:-}" = "true" ]; then
    CMD="db-synthesizer-ng"
  else
    CMD="db-synthesizer"
  fi

  synth-prep
  "$CMD" \
    --config "$DATA_DIR"/node-config.json \
    --db "$DATA_DIR"/db \
    --bulk-credentials-file "$GENESIS_DIR/bulk.creds.all.json" \
    -a \
    -e "$1"
  synth-restore
)

wait-for-mempool() (
  while true; do
      [ "$(cardano-cli latest query tx-mempool info | jq -re .numberOfTxs || true)" = "0" ] && break;
    echo "Waiting for the mempool to settle..."
    sleep 2
  done
  echo "Mempool is clear..."
)

wait-for-tip() (
  TYPE="$1"
  TARGET="$2"

  while true; do
      [ "$(jq -re ".$TYPE" <<< "$(cardano-cli latest query tip)")" = "$TARGET" ] && break;
    sleep 2
  done
)
