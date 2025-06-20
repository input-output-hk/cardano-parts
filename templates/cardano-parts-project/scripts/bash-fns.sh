# shellcheck disable=SC2148
#
# Various bash helper fns which aren't used enough to move to just recipes.

# This can be used to simplify ssh sessions, rsync, ex:
#   ssh -o "$(ssm-proxy-cmd "$REGION")" "$INSTANCE_ID"
ssm-proxy-cmd() {
  echo "ProxyCommand=sh -c 'aws --region $1 ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p'"
}


# A handy transaction submission function with mempool monitoring.
# CARDANO_NODE_{NETWORK_ID,SOCKET_PATH}, TESTNET_MAGIC should already be exported.
submit() (
  set -euo pipefail
  TX_SIGNED="$1"

  TXID=$(cardano-cli latest transaction txid --tx-file "$TX_SIGNED")

  echo "Submitting $TX_SIGNED with txid $TXID..."
  cardano-cli latest transaction submit --tx-file "$TX_SIGNED"

  EXISTS="true"
  while [ "$EXISTS" = "true" ]; do
    EXISTS=$(cardano-cli latest query tx-mempool tx-exists "$TXID" | jq -r .exists)
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
