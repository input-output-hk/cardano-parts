# Include cardano governance related justfile recipes in this file.
# Doing so will make diffing and patching the main repo Justfile easier.

# Query the approval status of a governance action
query-gov-action-status ENV ACTION_ID ACTION_IDX:
  #!/usr/bin/env bash
  # Based initially on @gitmachtl's query vote analysis script found at:
  #   https://github.com/gitmachtl/scripts/blob/master/cardano/testnet/24c_queryVote.sh
  set -euo pipefail
  {{checkEnvWithoutOverride}}

  if ! [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^private$|^sanchonet$|^shelley-qa$|^demo$ ]]; then
    echo "Error: only node environments for mainnet, preprod, preview, private, sanchonet, shelley-qa and demo are supported"
    exit 1
  fi

  just set-default-cardano-env {{ENV}} "$MAGIC" "$PPID"
  export CARDANO_NODE_NETWORK_ID="$MAGIC"
  export TESTNET_MAGIC="$MAGIC"
  echo

  [ -n "${DEBUG:-}" ] && set -x

  TIP=$(just query-tip {{ENV}})
  if [ "$(jq -re .syncProgress <<< "$TIP")" != "100.00" ]; then
    echo "Please wait until the local tip of environment {{ENV}} is 100.00 before voting"
    exit 1
  fi

  if [ "$(jq -re .era <<< "$TIP")" != "Conway" ]; then
    echo "Governance actions cannot be queried until Conway era."
    echo "Try again once in Conway era."
    exit 1
  fi

  if [ "${USE_SHELL_BINS:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ -n "${UNSTABLE:-}" ] && [ "${UNSTABLE:-}" != "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ "${UNSTABLE:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli-ng"
  elif [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^shelley-qa$ ]]; then
    CARDANO_CLI="cardano-cli"
  elif [[ "$ENV" =~ ^private$|^sanchonet$ ]]; then
    CARDANO_CLI="cardano-cli-ng"
  fi

  # ANSI color setup; use Unicode for jq color compatibility
  BLUE="\u001b[94m"
  CYAN="\u001b[36m"
  GREEN="\u001b[92m"
  OFF="\u001b[0m"
  RED="\u001b[91m"

  # Colored status
  GREEN_CHECK="$GREEN✅"
  GREEN_NA="${GREEN}n/a"
  RED_X="$RED❌"

  # Arg setup
  ACTION_UTXO="{{ACTION_ID}}"
  ACTION_IDX="{{ACTION_IDX}}"
  ACTION_ID="$ACTION_UTXO$(printf "%02x\n" "$ACTION_IDX")"
  ACTION_BECH=$(bech32 gov_action <<< "$ACTION_ID")

  # Basic query info
  echo "Current voting status for:"
  echo "  ACTION_ID: $ACTION_ID"
  echo "  ACTION_BECH: $ACTION_BECH"
  echo

  CURRENT_EPOCH=$(jq -re .epoch <<< "$TIP")
  GOV_STATE=$(eval "$CARDANO_CLI" latest query gov-state 2> /dev/null)
  ACTION_STATE=$(jq -re ".proposals | to_entries[] | .value" 2> /dev/null <<< "$GOV_STATE")
  if ! ACTION=$(jq -re ". | select(.actionId.txId == \"$ACTION_UTXO\" and .actionId.govActionIx == $ACTION_IDX)" 2> /dev/null <<< "$ACTION_STATE"); then
    echo -e "${RED}ERROR:$OFF Action $ACTION_UTXO#$ACTION_IDX was not found in environment $ENV."
    echo "       If this action id is confirmed to be correct, the action may have expired and is no longer seen in the gov state query proposals key."
    exit 1
  fi

  DREP_DIST=$(eval "$CARDANO_CLI" latest query drep-stake-distribution --all-dreps 2> /dev/null)
  DREP_STAKE_TOTAL=$(jq -r '[del(.[] | select(.[0] == "drep-alwaysAbstain" or .[0] == "drep-alwaysNoConfidence")) | .[][1]] | add' <<< "$DREP_DIST" 2> /dev/null)
  DREP_NOCONF_TOTAL=$(jq -r '(.[] | select(.[0] == "drep-alwaysNoConfidence") | .[1]) // 0' <<< "$DREP_DIST" 2> /dev/null)
  echo "Some potentially useful metrics:"
  echo "  CURRENT_EPOCH: $CURRENT_EPOCH"
  echo "  DREP_STAKE_TOTAL: $DREP_STAKE_TOTAL"
  echo "  DREP_NOCONF_TOTAL: $DREP_NOCONF_TOTAL"

  POOL_DIST=$(eval "$CARDANO_CLI" latest query spo-stake-distribution --all-spos 2> /dev/null)
  POOL_STAKE_TOTAL=$(jq -r '[.[][1]] | add' <<< "$POOL_DIST" 2> /dev/null)
  echo "  POOL_STAKE_TOTAL: $POOL_STAKE_TOTAL"

  COMMITTEE_DIST=$(eval "$CARDANO_CLI" latest query committee-state \
    | jq -r '
      [ .committee | (to_entries[] | select(.value.hotCredsAuthStatus.tag == "MemberAuthorized") |
        [
          "\(.value.hotCredsAuthStatus.contents | keys[0])-\(.value.hotCredsAuthStatus.contents.keyHash // .value.hotCredsAuthStatus.contents.scriptHash)",
          1
        ]
      )
    ]' 2> /dev/null || true)

  if [ "$COMMITTEE_DIST" == "" ]; then
    COMMITTEE_DIST="[]"
  fi

  COMMITTEE_TOTAL=$(jq -r "([.[][1]] | add) // 0" <<< "$COMMITTEE_DIST" 2> /dev/null)
  COMMITTEE_THRESHOLD=$(jq -r '"\(.committee.threshold)" // 0' <<< "$GOV_STATE" 2> /dev/null)
  COMMITTEE_THRESHOLD_TYPE=$(jq -r "type" <<< "$COMMITTEE_THRESHOLD" 2> /dev/null)
  echo "  COMMITTEE_TOTAL: $COMMITTEE_TOTAL"

  case "$COMMITTEE_THRESHOLD_TYPE" in
    "object")
      {
        read -r numerator
        read -r denominator
      } <<< "$(jq -r '.numerator // "-", .denominator // "-"' <<< "$COMMITTEE_THRESHOLD")"
      COMMITTEE_THRESHOLD=$(bc <<< "scale=2; 100.00 * ${numerator} / ${denominator}")
      ;;

    "number")
      COMMITTEE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $COMMITTEE_THRESHOLD")
      ;;
  esac

  PPARAMS=$(eval "$CARDANO_CLI" latest query protocol-parameters)
  PROT_MAJOR_VER=$(jq -r ".protocolVersion.major // -1" <<< "$PPARAMS" 2> /dev/null)
  echo "  PROT_MAJOR_VER: $PROT_MAJOR_VER"

  {
    read -r ACTION_TAG
    read -r ACTION_CONTENTS
    read -r ACTION_ANCHOR_URL
    read -r ACTION_ANCHOR_HASH
    read -r ACTION_PROPOSED_IN_EPOCH
    read -r ACTION_EXPIRES_AFTER_EPOCH
    read -r ACTION_DEPOSIT_RETURN_KEY_TYPE
    read -r ACTION_DEPOSIT_RETURN_HASH
    read -r ACTION_DEPOSIT_RETURN_NETWORK
    read -r ACTION_DREP_VOTE_YES_COUNT
    read -r ACTION_DREP_VOTE_NO_COUNT
    read -r ACTION_DREP_ABSTAIN_COUNT
    read -r ACTION_POOL_VOTE_YES_COUNT
    read -r ACTION_POOL_VOTE_NO_COUNT
    read -r ACTION_POOL_ABSTAIN_COUNT
    read -r ACTION_COMMITTEE_VOTE_YES_COUNT
    read -r ACTION_COMMITTEE_VOTE_NO_COUNT
    read -r ACTION_COMMITTEE_ABSTAIN_COUNT
  } <<< "$(jq -r '
    .proposalProcedure.govAction.tag // "-",
    "\(.proposalProcedure.govAction.contents)" // "-",
    .proposalProcedure.anchor.url // "-",
    .proposalProcedure.anchor.dataHash // "-",
    .proposedIn // "-",
    .expiresAfter // "-",
    (.proposalProcedure.returnAddr.credential|keys[0]) // "-",
    (.proposalProcedure.returnAddr.credential|flatten[0]) // "-",
    .proposalProcedure.returnAddr.network // "-",
    (.dRepVotes | with_entries(select(.value | contains("Yes"))) | length),
    (.dRepVotes | with_entries(select(.value | contains("No"))) | length),
    (.dRepVotes | with_entries(select(.value | contains("Abstain"))) | length),
    (.stakePoolVotes | with_entries(select(.value | contains("Yes"))) | length),
    (.stakePoolVotes | with_entries(select(.value | contains("No"))) | length),
    (.stakePoolVotes | with_entries(select(.value | contains("Abstain"))) | length),
    (.committeeVotes | with_entries(select(.value | contains("Yes"))) | length),
    (.committeeVotes | with_entries(select(.value | contains("No"))) | length),
    (.committeeVotes | with_entries(select(.value | contains("Abstain"))) | length)' <<< "$ACTION")"

    echo "  ACTION_TAG: $ACTION_TAG"
    echo "  ACTION_ANCHOR_URL: $ACTION_ANCHOR_URL"
    echo "  ACTION_ANCHOR_HASH: $ACTION_ANCHOR_HASH"
    echo "  ACTION_PROPOSED_IN_EPOCH: $ACTION_PROPOSED_IN_EPOCH"
    echo "  ACTION_EXPIRES_AFTER_EPOCH: $ACTION_EXPIRES_AFTER_EPOCH"
    echo "  ACTION_DEPOSIT_RETURN_KEY_TYPE: $ACTION_DEPOSIT_RETURN_KEY_TYPE"
    echo "  ACTION_DEPOSIT_RETURN_HASH: $ACTION_DEPOSIT_RETURN_HASH"
    echo "  ACTION_DEPOSIT_RETURN_NETWORK: $ACTION_DEPOSIT_RETURN_NETWORK"

    # Generate lists with the DRep hashes that are voted yes, no or abstain.
    # Add a 'drep-' in front of each entry to mach up the syntax in the `drep-stake-distribution` json.
    {
      read -r DREP_HASH_YES
      read -r DREP_HASH_ABSTAIN
    } <<< "$(jq -r '
      "\(.dRepVotes | with_entries(select(.value | contains("Yes"))) | keys | ["drep-\(.[])"] )",
      "\(.dRepVotes | with_entries(select(.value | contains("Abstain"))) | keys | ["drep-\(.[])"])"
    ' <<< "$ACTION" 2> /dev/null)"

    {
      read -r DREP_STAKE_YES
      read -r DREP_STAKE_ABSTAIN
    } <<< "$(jq -r "
      ([ .[] | select(.[0]==${DREP_HASH_YES}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${DREP_HASH_ABSTAIN}[]) | .[1] ] | add) // 0
    " <<< "$DREP_DIST" 2> /dev/null)"

    # Calculate the acceptance percentage for the drep group
    if [ "$ACTION_TAG" != "NoConfidence" ]; then

      # Do a normal percentage calculation if not a `NoConfidence` action
      DREP_PCT=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_YES / ($DREP_STAKE_TOTAL + $DREP_NOCONF_TOTAL - $DREP_STAKE_ABSTAIN)" 2> /dev/null)
      [ "$DREP_PCT" == "" ] && DREP_PCT="0"
    else
      # Or, if a NoConfidence action, the always no confidence counts as yes
      DREP_PCT=$(bc <<< "scale=2; 100.00 * ($DREP_STAKE_YES + $DREP_NOCONF_TOTAL) / ($DREP_STAKE_TOTAL - $DREP_STAKE_ABSTAIN)" 2> /dev/null)
    fi

    # Generate lists with the pool hashes that are voted yes, no or abstain.
    {
      read -r POOL_HASH_YES
      read -r POOL_HASH_ABSTAIN
    } <<< "$(jq -r '
      "\(.stakePoolVotes | with_entries(select(.value | contains("Yes"))) | keys )",
      "\(.stakePoolVotes | with_entries(select(.value | contains("Abstain"))) | keys)"
    ' <<< "$ACTION" 2> /dev/null)"

    # Calculate the total power of the yes, no and abstain keys
    {
      read -r POOL_STAKE_YES
      read -r POOL_STAKE_ABSTAIN
    } <<< "$(jq -r "
      ([ .[] | select(.[0]==${POOL_HASH_YES}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${POOL_HASH_ABSTAIN}[]) | .[1] ] | add) // 0
    " <<< "$POOL_DIST" 2> /dev/null)"

    # Calculate the acceptance percentage for the Pool group
    POOL_PCT=$(bc <<< "scale=2; (100.00 * $POOL_STAKE_YES) / ($POOL_STAKE_TOTAL - $POOL_STAKE_ABSTAIN)")

    # Generate lists with the committee hashes that are voted yes, no or abstain.
    {
      read -r COMMITTEE_HASH_YES
      read -r COMMITTEE_HASH_ABSTAIN
    } <<< "$(jq -r '
      "\(.committeeVotes | with_entries(select(.value | contains("Yes"))) | keys )",
      "\(.committeeVotes | with_entries(select(.value | contains("Abstain"))) | keys)"
    ' <<< "$ACTION" 2> /dev/null)"

    # Calculate the total power of the yes, no and abstain keys
    {
      read -r COMMITTEE_YES
      read -r COMMITTEE_ABSTAIN
    } <<< "$(jq -r "
      ([ .[] | select(.[0]==${COMMITTEE_HASH_YES}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${COMMITTEE_HASH_ABSTAIN}[]) | .[1] ] | add) // 0
    " <<< "$COMMITTEE_DIST" 2> /dev/null)"

    # Calculate the percentage for the committee
    if [ $((COMMITTEE_TOTAL - COMMITTEE_ABSTAIN)) -eq 0 ]; then
      COMMITTEE_PCT="0"
    else
      COMMITTEE_PCT=$(bc <<< "scale=2; (100.00 * $COMMITTEE_YES) / ($COMMITTEE_TOTAL - $COMMITTEE_ABSTAIN)")
    fi
  echo

  COMMITTEE_ACCEPT_ICON=""
  DREP_ACCEPT_ICON=""
  DREP_STAKE_THRESHOLD="N/A"
  POOL_ACCEPT_ICON=""
  POOL_STAKE_THRESHOLD="N/A"
  TOTAL_ACCEPT=""
  TOTAL_ACCEPT_ICON=""

  PREV_ACTION() {
    PREV_ACTION_UTXO="$1"
    PREV_ACTION_IDX="$2"

    if [ "${#PREV_ACTION_UTXO}" -gt 1 ]; then
      echo -e "Reference-Action-ID: $GREEN${PREV_ACTION_UTXO}#${PREV_ACTION_IDX}$OFF\n"
    fi
  }

  ACTION_CONTENT() {
    COLOR="$1"
    DESCRIPTION="$2"
    echo -e "Action-Content: $COLOR$DESCRIPTION$OFF\n"
  }

  THRESHOLD_CHECK() {
    TYPE="$1"
    PCT="$2"
    THRESHOLD="$3"
    if [ "$(bc <<< "$PCT >= $THRESHOLD")" -eq 1 ]; then
      case "$TYPE" in
        DREP) DREP_ACCEPT_ICON="$GREEN_CHECK" ;;
        POOL) POOL_ACCEPT_ICON="$GREEN_CHECK" ;;
        COMMITTEE) COMMITTEE_ACCEPT_ICON="$GREEN_CHECK" ;;
      esac
    else
      case "$TYPE" in
        DREP) DREP_ACCEPT_ICON="$RED_X" ;;
        POOL) POOL_ACCEPT_ICON="$RED_X" ;;
        COMMITTEE) COMMITTEE_ACCEPT_ICON="$RED_X" ;;
      esac
      TOTAL_ACCEPT+="NO"
    fi
  }

  # Participation per action type obtained from:
  #   https://developers.cardano.org/docs/governance/cardano-governance/governance-actions/#voting-thresholds-and-participants
  case "$ACTION_TAG" in
    "InfoAction")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
      } <<< "$(jq -r '
        .txId // "-",
        .govActionIx // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      echo -e "Action-Content:$CYAN Information$OFF"
      echo

      DREP_STAKE_THRESHOLD="n/a"
      POOL_STAKE_THRESHOLD="n/a"
      COMMITTEE_THRESHOLD="n/a"

      DREP_ACCEPT_ICON="$GREEN_NA"
      POOL_ACCEPT_ICON="$GREEN_NA"
      COMMITTEE_ACCEPT_ICON="$GREEN_NA"
      TOTAL_ACCEPT="N/A"
    ;;

    "HardForkInitiation")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
        read -r FORK_MAJOR_VER
        read -r FORK_MINOR_VER
      } <<< "$(jq -r '
        .[0].txId // "-",
        .[0].govActionIx // "-",
        .[1].major // "-",
        .[1].minor // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$GREEN" "Do a Hardfork"
      echo -e "Fork to ${GREEN}Protocol-Version$OFF ► $BLUE${FORK_MAJOR_VER}.${FORK_MINOR_VER}$OFF"
      echo

      {
        read -r DREP_STAKE_THRESHOLD
        read -r POOL_STAKE_THRESHOLD
      } <<< "$(jq -r '
        .dRepVotingThresholds.hardForkInitiation // 0,
        .poolVotingThresholds.hardForkInitiation // 0
      ' <<< "$PPARAMS" 2> /dev/null)"

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      if [ "$PROT_MAJOR_VER" -ge 10 ]; then
        THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"
      fi

      POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
      THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"

      THRESHOLD_CHECK "COMMITTEE" "$COMMITTEE_PCT" "$COMMITTEE_THRESHOLD"
    ;;

    "ParameterChange")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
        read -r CHANGE_PARAMETERS
      } <<< "$(jq -r '
        .[0].txId // "-",
        .[0].govActionIx // "-",
        "\(.[1])" // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$GREEN" "Change protocol parameters"
      CHANGE_PARAMETERS_RENDER=$(jq -r "to_entries[] | \"Change parameter $GREEN\(.key)$OFF ► $BLUE\(.value)$OFF\"" <<< "$CHANGE_PARAMETERS" 2> /dev/null)
      echo -e "$CHANGE_PARAMETERS_RENDER"
      echo

      DREP_STAKE_THRESHOLD="0"
      case "${CHANGE_PARAMETERS}" in
        # Security group - SPOs must vote, see:
        #   https://github.com/cardano-foundation/CIPs/tree/master/CIP-1694#protocol-parameter-groups
        *"maxBlockBodySize"*|*"maxTxSize"*|*"maxBlockHeaderSize"*|*"maxValueSize"*|*"maxBlockExecutionUnits"*|*"txFeePerByte"*|*"txFeeFixed"*|*"utxoCostPerByte"*|*"govActionDeposit"*|*"minFeeRefScriptCostPerByte"*)
          POOL_STAKE_THRESHOLD=$(jq -r '.poolVotingThresholds.ppSecurityGroup // 0' <<< "${PPARAMS}" 2> /dev/null)
          POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
          THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"
          echo -e "A parameter from the ${GREEN}SECURITY$OFF group is present ► ${BLUE}StakePools must vote$OFF"
          ;;&

        # Network group
        *"maxBlockBodySize"*|*"maxTxSize"*|*"maxBlockHeaderSize"*|*"maxValueSize"*|*"maxTxExecutionUnits"*|*"maxBlockExecutionUnits"*|*"maxCollateralInputs"*)
          DREP_STAKE_THRESHOLD=$(jq -r "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppNetworkGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}NETWORK$OFF group"
          ;;&

        # Economic group
        *"txFeePerByte"*|*"txFeeFixed"*|*"stakeAddressDeposit"*|*"stakePoolDeposit"*|*"monetaryExpansion"*|*"treasuryCut"*|*"minPoolCost"*|*"utxoCostPerByte"*|*"executionUnitPrices"*)
          DREP_STAKE_THRESHOLD=$(jq -r "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppEconomicGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}ECONOMIC$OFF group"
          ;;&

        # Technical group
        *"poolPledgeInfluence"*|*"poolRetireMaxEpoch"*|*"stakePoolTargetNum"*|*"costModels"*|*"collateralPercentage"*)
          DREP_STAKE_THRESHOLD=$(jq -r "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppTechnicalGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}TECHNICAL$OFF group"
          ;;&

        # Governance group
        *"govActionLifetime"*|*"govActionDeposit"*|*"dRepDeposit"*|*"dRepActivity"*|*"committeeMinSize"*|*"committeeMaxTermLength"*|*"VotingThresholds"*)
          DREP_STAKE_THRESHOLD=$(jq -r "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppGovGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}GOVERNANCE$OFF group"
          ;;
      esac
      echo

      if [ "$DREP_STAKE_THRESHOLD" == "0" ] || [ "$DREP_STAKE_THRESHOLD" == "" ]; then
        echo -e "${RED}ERROR - Something went wrong finding the drep stake threshold.$OFF"
        exit 1
      fi

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      if [ "$PROT_MAJOR_VER" -ge 10 ]; then
        THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"
      fi

      THRESHOLD_CHECK "COMMITTEE" "$COMMITTEE_PCT" "$COMMITTEE_THRESHOLD"
      ;;

    "NewConstitution")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
        read -r ANCHOR_HASH
        read -r ANCHOR_URL
        read -r SCRIPT_HASH
      } <<< "$(jq -r '
        .[0].txId // "-",
        .[0].govActionIx // "-",
        .[1].anchor.dataHash // "-",
        .[1].anchor.url // "-",
        .[1].script // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$GREEN" "Change to a new constitution"

      echo -e "Set new ${GREEN}Constitution-URL$OFF ► $BLUE$ANCHOR_URL$OFF"
      echo -e "Set new ${GREEN}Constitution-Hash$OFF ► $BLUE$ANCHOR_HASH$OFF"
      echo -e "Set new ${GREEN}Guardrails-Script-Hash$OFF ► $BLUE$SCRIPT_HASH$OFF"
      echo

      DREP_STAKE_THRESHOLD=$(jq -r '.dRepVotingThresholds.updateToConstitution // 0' <<< "$PPARAMS" 2> /dev/null)
      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"

      POOL_ACCEPT_ICON=""

      THRESHOLD_CHECK "COMMITTEE" "$COMMITTEE_PCT" "$COMMITTEE_THRESHOLD"
      ;;

    "UpdateCommittee")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
        read -r COMMITTEE_KEY_HASHES_REMOVE
        read -r COMMITTEE_KEY_HASHES_ADD
        read -r COMMITTEE_THRESHOLD
      } <<< "$(jq -r '
        .[0].txId // "-",
        .[0].govActionIx // "-",
        "\(.[1])" // "[]",
        "\(.[2])" // "[]",
        "\(.[3])" // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$GREEN" "Threshold ->"

      COMMITTEE_KEY_HASHES_ADD=$(jq -r "keys" <<< "$COMMITTEE_KEY_HASHES_ADD" 2> /dev/null)
      COMMITTEE_KEY_HASHES_REMOVE=$(jq -r "[.[].keyHash]" <<< "$COMMITTEE_KEY_HASHES_REMOVE" 2> /dev/null)
      COMMITTEE_THRESHOLD_TYPE=$(jq -r "type" <<< "$COMMITTEE_THRESHOLD" 2> /dev/null)

      case "$COMMITTEE_THRESHOLD_TYPE" in
        "object")
          {
            read -r NUMERATOR
            read -r DENOMINATOR
          } <<< "$(jq -r '.numerator // "-", .denominator // "-"' <<< "$COMMITTEE_THRESHOLD")"
          echo -e "Approval of a governance measure requires $NUMERATOR out of $DENOMINATOR ($(bc <<< "scale=0; ($NUMERATOR * 100 / $DENOMINATOR) / 1")%) of the votes of committee members.$OFF\n"
          ;;

        "number")
          echo -e "Approval of a governance measure requires $(bc <<< "scale=0; ($COMMITTEE_THRESHOLD * 100) / 1")% of the votes of committee members.$OFF\n"
          ;;
      esac

      ADD_HASHES_RENDER=$(jq -r "
        .[2] // {}
          | to_entries[]
          | \"Adding $GREEN\(.key)-\(.value)\"
          | split(\"-\") | \"\(.[0])$OFF ► $BLUE\(.[1])$OFF (max term epoch \(.[2]))\"
      " <<< "$ACTION_CONTENTS" 2> /dev/null)

      REM_HASHES_RENDER=$(jq -r "
        .[1][] // []
          | to_entries[]
          | \"Remove $GREEN\(.key)$OFF ◄ $RED\(.value)$OFF\"
      " <<< "$ACTION_CONTENTS" 2> /dev/null)

      echo -e "$ADD_HASHES_RENDER"
      echo -e "$REM_HASHES_RENDER"

      {
        read -r DREP_STAKE_THRESHOLD
        read -r POOL_STAKE_THRESHOLD
      } <<< "$(jq -r '.dRepVotingThresholds.committeeNormal // 0, .poolVotingThresholds.committeeNormal // 0' <<< "$PPARAMS" 2> /dev/null)"

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"

      POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
      THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"

      COMMITTEE_ACCEPT_ICON="";
      ;;

    "NoConfidence")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
      } <<< "$(jq -r '.txId // "-", .govActionIx // "-"' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$RED" "No confidence in the committee"

      {
        read -r DREP_STAKE_THRESHOLD
        read -r POOL_STAKE_THRESHOLD
      } <<< "$(jq -r '
        .dRepVotingThresholds.committeeNoConfidence // 0,
        .poolVotingThresholds.committeeNoConfidence // 0
      ' <<< "$PPARAMS" 2> /dev/null)"

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"

      POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
      THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"

      COMMITTEE_ACCEPT_ICON=""
      ;;

    "TreasuryWithdrawals")
      {
        read -r WITHDRAWALS_AMOUNT
        read -r WITHDRAWALS_KEY_TYPE
        read -r WITHDRAWALS_HASH
        read -r WITHDRAWALS_NETWORK
      } <<< "$(jq -r '
        .[0][0][1] // "0",
        (.[0][0][0].credential|keys[0]) // "-",
        (.[0][0][0].credential|flatten[0]) // "-",
        .[0][0][0].network // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      ACTION_CONTENT "$GREEN" "Withdrawal of funds from the treasury"

      # Lowercase the case comparison variables with bash parameter expansion
      case "${WITHDRAWALS_NETWORK,,}${WITHDRAWALS_KEY_TYPE,,}" in
        *"scripthash")
          echo -e "Withdrawal to ${GREEN}ScriptHash$OFF ► $BLUE$WITHDRAWALS_HASH$OFF"
          ;;

        "mainnet"*)
          if WITHDRAWALS_ADDR=$(bech32 "stake" <<< "e1$WITHDRAWALS_HASH" 2> /dev/null); then
            echo -e "Withdrawal to ${GREEN}stake addr$OFF ► $BLUE$WITHDRAWALS_ADDR$OFF"
          else
            echo -e "${RED}ERROR:$OFF Could not get withdrawal stake address from key hash $WITHDRAWALS_HASH"
            exit 1
          fi
          ;;

        "testnet"*)
          if WITHDRAWALS_ADDR=$(bech32 "stake_test" <<< "e0$WITHDRAWALS_HASH" 2> /dev/null); then
            echo -e "Withdrawal to ${GREEN}stake addr$OFF ► $BLUE$WITHDRAWALS_ADDR$OFF"
          else
            echo -e "${RED}ERROR:$OFF Could not get withdrawal stake address from key hash $WITHDRAWALS_HASH"
            exit 1
          fi
          ;;

        "")
          echo -e "Withdrawal ${GREEN}directly$OFF to the ${BLUE}deposit return address$OFF"
          ;;

        *)
          echo -e "${RED}ERROR:$OFF Unknown network type $WITHDRAWALS_NETWORK for the withdrawal key hash"
          exit 1;
          ;;
      esac

      echo -e "Withdrawal the ${GREEN}amount$OFF ► $BLUE$WITHDRAWALS_AMOUNT lovelaces$OFF"
      echo

      DREP_STAKE_THRESHOLD=$(jq -r '.dRepVotingThresholds.treasuryWithdrawal // 0' <<< "$PPARAMS" 2> /dev/null)
      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      if [ "$PROT_MAJOR_VER" -ge 10 ]; then
        THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"
      fi

      POOL_ACCEPT_ICON=""

      THRESHOLD_CHECK "COMMITTEE" "$COMMITTEE_PCT" "$COMMITTEE_THRESHOLD"
      ;;
  esac

  OUTPUT="Current Votes,Yes,No,Abstain,Threshold,Live-Pct,Accept"

  if [ "$DREP_ACCEPT_ICON" != "" ]; then
    DREP_SUMMARY="Dreps,$ACTION_DREP_VOTE_YES_COUNT,$ACTION_DREP_VOTE_NO_COUNT,$ACTION_DREP_ABSTAIN_COUNT,$DREP_STAKE_THRESHOLD,$DREP_PCT,$DREP_ACCEPT_ICON"
  else
    DREP_SUMMARY="Dreps,-,-,-,-,-,"
  fi

  if [ "$POOL_ACCEPT_ICON" != "" ]; then
    POOL_SUMMARY="StakePools,$ACTION_POOL_VOTE_YES_COUNT,$ACTION_POOL_VOTE_NO_COUNT,$ACTION_POOL_ABSTAIN_COUNT,$POOL_STAKE_THRESHOLD,$POOL_PCT,$POOL_ACCEPT_ICON"
  else
    POOL_SUMMARY="StakePools,-,-,-,-,-,"
  fi


  if [ "$COMMITTEE_ACCEPT_ICON" != "" ]; then
    COMMITTEE_SUMMARY="Committee,$ACTION_COMMITTEE_VOTE_YES_COUNT,$ACTION_COMMITTEE_VOTE_NO_COUNT,$ACTION_COMMITTEE_ABSTAIN_COUNT,$COMMITTEE_THRESHOLD,$COMMITTEE_PCT,$COMMITTEE_ACCEPT_ICON"
  else
    COMMITTEE_SUMMARY="Committee,-,-,-,-,-,"
  fi

  echo -e "$OUTPUT\n$DREP_SUMMARY\n$POOL_SUMMARY\n$COMMITTEE_SUMMARY" | nu --stdin -c "\$in | from csv --separator ','"

  case "$TOTAL_ACCEPT" in
    *"N/A"*) TOTAL_ACCEPT_ICON="$GREEN_NA";;
    *"NO"*) TOTAL_ACCEPT_ICON="$RED_X";;
    *) TOTAL_ACCEPT_ICON="$GREEN_CHECK";;
  esac

  echo -e "Full approval of the proposal: $TOTAL_ACCEPT_ICON"


# Generate and submit an SPO vote on a gov action
vote-with-pool ENV POOL ACTION_ID ACTION_IDX VOTE:
  #!/usr/bin/env bash
  set -euo pipefail
  {{checkEnvWithoutOverride}}

  if ! [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^private$|^sanchonet$|^shelley-qa$|^demo$ ]]; then
    echo "Error: only node environments for mainnet, preprod, preview, private, sanchonet, shelley-qa and demo are supported"
    exit 1
  fi

  just set-default-cardano-env {{ENV}} "$MAGIC" "$PPID"
  export CARDANO_NODE_NETWORK_ID="$MAGIC"
  export TESTNET_MAGIC="$MAGIC"
  echo

  if [ "$(jq -re .syncProgress <<< "$(just query-tip {{ENV}})")" != "100.00" ]; then
    echo "Please wait until the local tip of environment {{ENV}} is 100.00 before voting"
    exit 1
  fi

  if ! [[ "{{VOTE}}" =~ ^yes$|^no$|^abstain$ ]]; then
    echo "Error: VOTE arg must be one of \"yes\", \"no\" or \"abstain\""
    exit 1
  fi

  if [ "${USE_SHELL_BINS:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ -n "${UNSTABLE:-}" ] && [ "${UNSTABLE:-}" != "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ "${UNSTABLE:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli-ng"
  elif [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^shelley-qa$ ]]; then
    CARDANO_CLI="cardano-cli"
  elif [[ "$ENV" =~ ^private$|^sanchonet$ ]]; then
    CARDANO_CLI="cardano-cli-ng"
  fi

  STATE_BEFORE=$(eval "$CARDANO_CLI" latest query gov-state)
  ACTION_BEFORE=$(
    jq -r \
      --arg actionId {{ACTION_ID}} \
      --arg actionIdx {{ACTION_IDX}} \
      '.proposals | map(
        select(
          .actionId.txId == $actionId
            and
          .actionId.govActionIx == ($actionIdx | tonumber)
        )
      )' \
      <<< "$STATE_BEFORE"
  )

  echo
  echo "Governance action {{ACTION_ID}}#{{ACTION_IDX}} has the following associated gov state:"
  echo
  echo "$ACTION_BEFORE"
  echo
  read -p "Do you wish pool \"{{POOL}}\" in environment \"{{ENV}}\" to vote \"{{VOTE}}\" on this governance action [yY]? " -n 1 -r
  echo
  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting the vote."
    exit 1
  fi

  FILE="{{POOL}}-{{ACTION_ID}}#{{ACTION_IDX}}"

  # An assumption is made here that users have their secret cold as $POOL-cold.skey.
  # The vkey may be listed in both the deploy and no-deploy poolgroup directories,
  # so limit the output to the first match.
  COLD_SKEY=$(fd --max-results 1 {{POOL}}-cold.skey secrets)
  COLD_VKEY=$(fd --max-results 1 {{POOL}}-cold.vkey secrets)

  # Assume secrets are properly encrypted
  eval "$CARDANO_CLI" latest governance vote create \
    --{{VOTE}} \
    --governance-action-tx-id {{ACTION_ID}} \
    --governance-action-index {{ACTION_IDX}} \
    --cold-verification-key-file <(just sops-decrypt-binary "$COLD_VKEY") \
    --out-file "$FILE.vote"

  echo
  echo "The created vote to be submitted is the following:"
  echo
  eval "$CARDANO_CLI" latest governance vote view \
    --vote-file "$FILE.vote"
  echo
  echo
  read -p "Do you wish to proceed with this vote [yY]? " -n 1 -r
  echo
  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting the vote."
    exit 1
  fi

  RICH_ADDR=$(just sops-decrypt-binary secrets/envs/${ENV}/utxo-keys/rich-utxo.addr)

  # Select the smallest available UTxO without native tokens attached and greater than 5 ADA automatically with jq:
  RICH_UTXOS=$(eval "$CARDANO_CLI" latest query utxo --address "$RICH_ADDR" --out-file /dev/stdout)

  TX_SELECTED=$(jq -r '.
    | to_entries
    | map(select((.value.value | length == 1) and .value.value.lovelace > 5000000))
    | sort_by(.value.value.lovelace)[0]' <<< "$RICH_UTXOS"
  )

  TXIN=$(jq -r '.key' <<< "$TX_SELECTED")
  TXVALUE=$(jq -r '.value.value.lovelace' <<< "$TX_SELECTED")

  echo
  echo "Selected rich key funding TX \"$TXIN\" with value $TXVALUE lovelace"

  eval "$CARDANO_CLI" latest transaction build \
    --tx-in "$TXIN" \
    --change-address "$RICH_ADDR" \
    --testnet-magic "$TESTNET_MAGIC" \
    --vote-file "$FILE.vote" \
    --witness-override 2 \
    --out-file "$FILE.raw"

  eval "$CARDANO_CLI" latest transaction sign \
    --tx-body-file "$FILE.raw" \
    --signing-key-file <(just sops-decrypt-binary secrets/envs/${ENV}/utxo-keys/rich-utxo.skey) \
    --signing-key-file <(just sops-decrypt-binary "$COLD_SKEY") \
    --testnet-magic "$TESTNET_MAGIC" \
    --out-file "$FILE.signed"

  TXID=$(eval "$CARDANO_CLI" latest transaction txid --tx-file "$FILE.signed")

  echo
  echo "The signed vote containing transaction with txid \"$TXID\" is the following:"
  echo

  eval "$CARDANO_CLI" debug transaction view --tx-file "$FILE.signed"

  echo
  echo
  read -p "Do you wish to submit this vote to the {{ENV}} network [yY]? " -n 1 -r
  echo
  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting the vote."
    exit 1
  fi

  echo
  echo "Submitting the vote."

  eval "$CARDANO_CLI" latest transaction submit --tx-file "$FILE.signed"

  EXISTS="true"

  while [ "$EXISTS" = "true" ]; do
    EXISTS=$(eval "$CARDANO_CLI" latest query tx-mempool tx-exists $TXID | jq -r .exists)
    if [ "$EXISTS" = "true" ]; then
      echo "Vote transaction still exists in the mempool, sleeping 5s: $TXID"
    else
      echo "Vote transaction has been removed from the mempool."
    fi
    sleep 5
  done
  echo
  echo

  STATE_AFTER=$(eval "$CARDANO_CLI" latest query gov-state)
  ACTION_AFTER=$(
    jq -r \
      --arg actionId {{ACTION_ID}} \
      --arg actionIdx {{ACTION_IDX}} \
      '.proposals | map(
        select(
          .actionId.txId == $actionId
            and
          .actionId.govActionIx == ($actionIdx | tonumber)
        )
      )' \
      <<< "$STATE_AFTER"
  )

  echo "Differences in gov action state before and after submitting the vote transaction with txid \"$TXID\" are:"
  echo

  icdiff -L beforeTxSubmission -L afterTxSubmission <(echo "$ACTION_BEFORE") <(echo "$ACTION_AFTER")
