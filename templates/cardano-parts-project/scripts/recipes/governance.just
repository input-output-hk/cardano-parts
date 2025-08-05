# Include cardano governance related justfile recipes in this file.
# Doing so will make diffing and patching the main repo Justfile easier.

# Query the approval status of a governance action
query-gov-action-status ENV ACTION_ID ACTION_IDX:
  #!/usr/bin/env bash
  # Based initially on @gitmachtl's query vote analysis script found at:
  #   https://github.com/gitmachtl/scripts/blob/master/cardano/testnet/24c_queryVote.sh
  set -euo pipefail
  {{checkEnvWithoutOverride}}

  if ! [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^demo$ ]]; then
    echo "Error: only node environments for mainnet, preprod and preview and demo are supported"
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
  elif [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$ ]]; then
    CARDANO_CLI="cardano-cli"
  fi

  # ANSI color setup; use Unicode for jq color compatibility
  BLUE="\u001b[94m"
  CYAN="\u001b[36m"
  GRAY="\u001b[90m"
  GREEN="\u001b[92m"
  OFF="\u001b[0m"
  RED="\u001b[91m"

  # Colored status
  GREEN_CHECK="$GREEN✅"
  GREEN_NA="${GREEN}n/a"
  RED_X="$RED❌"

  # Check cardano-cli requirements:
  CLI_VERSION=$(eval "$CARDANO_CLI" --version | grep -oP "cardano-cli \K[0-9.]+")
  if [ "$(nix eval --impure --expr 'let f = builtins.getFlake "git+file://${toString ./.}"; in f.lib.versionAtLeast "'"$CLI_VERSION"'" "10.2.0.0"')" != "true" ]; then
    echo -e "${RED}ERROR:${OFF}"
    echo -e "  The cardano-cli version must be at least ${GREEN}10.2.0.0${OFF}."
    echo -e "  Your version is ${RED}$CLI_VERSION${OFF}."
    echo
    echo -e "  For the latest version of cardano-cli available from cardano-parts, try running:"
    echo
    echo -e "  export UNSTABLE=true"
    exit 1
  fi

  L_JUSTIFY() {
    DESC="$1"
    VALUE="$2"
    COL="$3"

    printf "  %s%*s%s\n" "$DESC" $((COL - ${#DESC})) "" "$VALUE"
  }

  R_JUSTIFY() {
    DESC="$1"
    VALUE="$2"
    COL="$3"

    printf "  %s%*s%s\n" "$DESC" $((COL - ${#DESC} - ${#VALUE})) "" "$VALUE"
  }

  # Arg setup
  ACTION_UTXO="{{ACTION_ID}}"
  ACTION_IDX="{{ACTION_IDX}}"
  ACTION_ID="$ACTION_UTXO$(printf "%02x\n" "$ACTION_IDX")"
  ACTION_BECH=$(bech32 gov_action <<< "$ACTION_ID")

  # Basic query info
  echo "Current voting status for:"
  L_JUSTIFY "ACTION_ID:" "$ACTION_ID" 35
  L_JUSTIFY "ACTION_BECH:" "$ACTION_BECH" 35
  echo

  CURRENT_EPOCH=$(jq -re .epoch <<< "$TIP")
  GOV_STATE=$(eval "$CARDANO_CLI" latest query gov-state 2> /dev/null)
  ACTION_STATE=$(jq -re ".proposals | to_entries[] | .value" 2> /dev/null <<< "$GOV_STATE" || true)
  if ! ACTION=$(jq -re ". | select(.actionId.txId == \"$ACTION_UTXO\" and .actionId.govActionIx == $ACTION_IDX)" 2> /dev/null <<< "$ACTION_STATE"); then
    echo -e "${RED}ERROR:$OFF Action $ACTION_UTXO#$ACTION_IDX was not found in environment $ENV."
    echo "       If this action id is confirmed to be correct, the action may have expired and is no longer seen in the gov state query proposals key."
    exit 1
  fi

  EPOCH=$(jq -re .epoch <<< "$TIP")

  # The drep-stake-distribution query includes expired dreps and system
  # alwaysAbstain and alwaysNoConfidence dreps which are funded directly from
  # stake delegation.
  DREP_DIST=$(eval "$CARDANO_CLI" latest query drep-stake-distribution --all-dreps 2> /dev/null | jq 'to_entries | map([.key, .value])')

  # DREP_PWR_DIST is similar to DREP_DIST but excludes expired dreps and system dreps (alwaysAbstain and alwaysNoConfidence).
  DREP_PWR_DIST=$(eval "$CARDANO_CLI" latest query drep-state --all-dreps --include-stake \
    | jq -re "[ .[] | select( .[1].expiry >= $EPOCH ) | [\"drep-\(.[0] | keys[0])-\(.[0] | to_entries[].value)\", (.[1].stake // 0)]]" 2> /dev/null)

  # Get a distribution of all expired dreps
  DREP_EXP_PWR_DIST=$(eval "$CARDANO_CLI" latest query drep-state --all-dreps --include-stake \
    | jq -re "[ .[] | select( .[1].expiry < $EPOCH ) | [\"drep-\(.[0] | keys[0])-\(.[0] | to_entries[].value)\", (.[1].stake // 0)]]" 2> /dev/null)

  # Calculate active and inactive drep power based on valid or expired dreps
  DREP_PWR_ACTIVE=$(jq -re "[.[][1]] | add // 0" <<< "$DREP_PWR_DIST" 2> /dev/null)
  DREP_PWR_INACTIVE=$(jq -re "[.[][1]] | add // 0" <<< "$DREP_EXP_PWR_DIST" 2> /dev/null)

  # All drep stake, including stake held by expired dreps, and stake auto delegated to always abstain or always no-confidence
  DREP_STAKE_TOTAL=$(jq -re '[.[][1]] | add' <<< "$DREP_DIST" 2> /dev/null)

  # This is always 1 length for drep-alwaysNoConfidence;
  DREP_NOCONF_COUNT=$(jq -re '[.[] | select(.[0] == "drep-alwaysNoConfidence") | .[1]] | length' <<< "$DREP_DIST" 2> /dev/null)
  DREP_NOCONF_TOTAL=$(jq -re '(.[] | select(.[0] == "drep-alwaysNoConfidence") | .[1]) // 0' <<< "$DREP_DIST" 2> /dev/null)

  DREP_ALWAYS_ABSTAIN_TOTAL=$(jq -re '(.[] | select(.[0] == "drep-alwaysAbstain") | .[1]) // 0' <<< "$DREP_DIST" 2> /dev/null)
  echo "Some useful metrics:"
  R_JUSTIFY "CURRENT_EPOCH:" "$CURRENT_EPOCH" 50
  R_JUSTIFY "DREP_POWER_ACTIVE:" "$DREP_PWR_ACTIVE" 50
  R_JUSTIFY "DREP_POWER_INACTIVE:" "$DREP_PWR_INACTIVE" 50
  R_JUSTIFY "DREP_STAKE_TOTAL:" "$DREP_STAKE_TOTAL" 50
  R_JUSTIFY "DREP_NOCONF_TOTAL:" "$DREP_NOCONF_TOTAL" 50
  R_JUSTIFY "DREP_ALWAYS_ABSTAIN:" "$DREP_ALWAYS_ABSTAIN_TOTAL" 50

  POOL_DIST=$(eval "$CARDANO_CLI" latest query spo-stake-distribution --all-spos 2> /dev/null)
  POOL_STAKE_TOTAL=$(jq -re '[.[][1]] | add // 0' <<< "$POOL_DIST" 2> /dev/null)
  POOL_ABSTAIN_TOTAL=$(jq -re '[(.[] | select(.[2] == "drep-alwaysAbstain")) | .[1]] | add // 0' <<< "$POOL_DIST")
  POOL_NOCONF_TOTAL=$(jq -re '[(.[] | select(.[2] == "drep-alwaysNoConfidence")) | .[1]] | add // 0' <<< "$POOL_DIST")

  R_JUSTIFY "POOL_STAKE_TOTAL:" "$POOL_STAKE_TOTAL" 50
  R_JUSTIFY "POOL_ABSTAIN_TOTAL:" "$POOL_ABSTAIN_TOTAL" 50
  R_JUSTIFY "POOL_NOCONF_TOTAL:" "$POOL_NOCONF_TOTAL" 50

  COMMITTEE_DIST=$(eval "$CARDANO_CLI" latest query committee-state \
    | jq -re '
      [ .committee | (to_entries[] | select(.value.hotCredsAuthStatus.tag == "MemberAuthorized" and .value.status == "Active") |
        [
          "\(.value.hotCredsAuthStatus.contents | keys[0])-\(.value.hotCredsAuthStatus.contents.keyHash // .value.hotCredsAuthStatus.contents.scriptHash)",
          1
        ]
      )
    ]' 2> /dev/null || true)

  if [ "$COMMITTEE_DIST" == "" ]; then
    COMMITTEE_DIST="[]"
  fi

  COMMITTEE_TOTAL=$(jq -re "length // 0" <<< "$COMMITTEE_DIST" 2> /dev/null)
  COMMITTEE_THRESHOLD=$(jq -re '"\(.committee.threshold)" // 0' <<< "$GOV_STATE" 2> /dev/null)
  COMMITTEE_THRESHOLD_TYPE=$(jq -re "type" <<< "$COMMITTEE_THRESHOLD" 2> /dev/null)
  R_JUSTIFY "COMMITTEE_TOTAL:" "$COMMITTEE_TOTAL" 50

  case "$COMMITTEE_THRESHOLD_TYPE" in
    "object")
      {
        read -r numerator
        read -r denominator
      } <<< "$(jq -re '.numerator // "-", .denominator // "-"' <<< "$COMMITTEE_THRESHOLD")"
      COMMITTEE_THRESHOLD=$(bc <<< "scale=2; 100.00 * ${numerator} / ${denominator}")
      ;;

    "number")
      COMMITTEE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $COMMITTEE_THRESHOLD")
      ;;
  esac
  COMMITTEE_THRESHOLD_TOTAL=$(bc <<< "scale=1; ($COMMITTEE_THRESHOLD * $COMMITTEE_TOTAL / 100) + 0.5")
  COMMITTEE_THRESHOLD_TOTAL=${COMMITTEE_THRESHOLD_TOTAL%%.*}

  PPARAMS=$(eval "$CARDANO_CLI" latest query protocol-parameters)
  PROT_MAJOR_VER=$(jq -re ".protocolVersion.major // -1" <<< "$PPARAMS" 2> /dev/null)
  R_JUSTIFY "PROT_MAJOR_VER:" "$PROT_MAJOR_VER" 50

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
  } <<< "$(jq -re '
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

    L_JUSTIFY "ACTION_TAG:" "$ACTION_TAG" 35
    L_JUSTIFY "ACTION_ANCHOR_URL:" "$ACTION_ANCHOR_URL" 35
    L_JUSTIFY "ACTION_ANCHOR_HASH:" "$ACTION_ANCHOR_HASH" 35
    L_JUSTIFY "ACTION_PROPOSED_IN_EPOCH:" "$ACTION_PROPOSED_IN_EPOCH" 35
    L_JUSTIFY "ACTION_EXPIRES_AFTER_EPOCH:" "$ACTION_EXPIRES_AFTER_EPOCH" 35
    L_JUSTIFY "ACTION_DEPOSIT_RETURN_KEY_TYPE:" "$ACTION_DEPOSIT_RETURN_KEY_TYPE" 35
    L_JUSTIFY "ACTION_DEPOSIT_RETURN_HASH:" "$ACTION_DEPOSIT_RETURN_HASH" 35
    L_JUSTIFY "ACTION_DEPOSIT_RETURN_NETWORK:" "$ACTION_DEPOSIT_RETURN_NETWORK" 35

    # Generate lists with the DRep hashes that are voted yes, no or abstain.
    # Add a 'drep-' in front of each entry to mach up the syntax in the `drep-stake-distribution` json.
    {
      read -r DREP_HASH_YES
      read -r DREP_HASH_NO
      read -r DREP_HASH_ABSTAIN
    } <<< "$(jq -re '
      "\(.dRepVotes | with_entries(select(.value | contains("Yes"))) | keys | ["drep-\(.[])"] )",
      "\(.dRepVotes | with_entries(select(.value | contains("No"))) | keys | ["drep-\(.[])"] )",
      "\(.dRepVotes | with_entries(select(.value | contains("Abstain"))) | keys | ["drep-\(.[])"])"
    ' <<< "$ACTION" 2> /dev/null)"

    {
      read -r DREP_STAKE_YES
      read -r DREP_STAKE_NO
      read -r DREP_STAKE_ABSTAIN
    } <<< "$(jq -re "
      ([ .[] | select(.[0]==${DREP_HASH_YES}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${DREP_HASH_NO}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${DREP_HASH_ABSTAIN}[]) | .[1] ] | add) // 0
    " <<< "$DREP_PWR_DIST" 2> /dev/null)"

    # Calculate the acceptance percentage for the drep group
    if [ "$ACTION_TAG" != "NoConfidence" ]; then
      # Do a normal percentage calculation if not a `NoConfidence` action
      # DREP_PWR_ACTIVE is drep stake for dreps who have not expired and it does not include alwaysNoConfidence or alwaysAbstain delegation
      # DREP_NOCONF_TOTAL is only from direct stake key delegation and should be counted in the denominator
      # DREP_STAKE_ABSTAIN is summed stake from explicit drep abstain votes
      # which need to be removed from threshold denominator; the system
      # alwaysAbstrain drep has already been excluded by using DREP_PWR_ACTIVE.
      DREP_PCT=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_YES / ($DREP_PWR_ACTIVE + $DREP_NOCONF_TOTAL - $DREP_STAKE_ABSTAIN)" 2> /dev/null)
    else
      # Or, if a `NoConfidence` action, the always no confidence counts as yes
      DREP_PCT=$(bc <<< "scale=2; 100.00 * ($DREP_STAKE_YES + $DREP_NOCONF_TOTAL) / ($DREP_PWR_ACTIVE + $DREP_NOCONF_TOTAL - $DREP_STAKE_ABSTAIN)" 2> /dev/null)
    fi
    DREP_TOTAL=$(bc <<< "$DREP_PWR_ACTIVE + $DREP_NOCONF_TOTAL - $DREP_STAKE_ABSTAIN" 2> /dev/null)
    [ "$DREP_PCT" == "" ] && DREP_PCT="0" && DREP_TOTAL="0"

    # Generate lists with the pool hashes that are voted yes, no or abstain.
    {
      read -r POOL_HASH_YES
      read -r POOL_HASH_NO
      read -r POOL_HASH_ABSTAIN
    } <<< "$(jq -re '
      "\(.stakePoolVotes | with_entries(select(.value | contains("Yes"))) | keys )",
      "\(.stakePoolVotes | with_entries(select(.value | contains("No"))) | keys )",
      "\(.stakePoolVotes | with_entries(select(.value | contains("Abstain"))) | keys)"
    ' <<< "$ACTION" 2> /dev/null)"

    # Calculate the total power of the yes, no and abstain keys
    {
      read -r POOL_STAKE_YES
      read -r POOL_STAKE_NO
      read -r POOL_STAKE_ABSTAIN
    } <<< "$(jq -re "
      ([ .[] | select(.[0]==${POOL_HASH_YES}[]) | .[1]] | add) // 0,
      ([ .[] | select(.[0]==${POOL_HASH_NO}[]) | .[1]] | add) // 0,
      ([ .[] | select(.[0]==${POOL_HASH_ABSTAIN}[]) | .[1]] | add) // 0
    " <<< "$POOL_DIST" 2> /dev/null)"

    POOL_NOT_VOTED_DIST=$(jq -re "[.[] | select(.[0] |
      IN($POOL_HASH_YES[]) or IN($POOL_HASH_NO[]) or IN($POOL_HASH_ABSTAIN[]) | not)]" \
    <<< "$POOL_DIST" 2> /dev/null)

    POOL_NOT_VOTED_TOTAL=$(jq -re '[del(.[] |
      select(.[2] == "drep-alwaysAbstain" or .[2] == "drep-alwaysNoConfidence")) | .[][1]] | add // 0' \
    <<< "$POOL_NOT_VOTED_DIST" 2> /dev/null)

    POOL_NOCONF_COUNT=$(jq -re '[.[] | select(.[2] == "drep-alwaysNoConfidence") | .[1]] | length' \
      <<< "$POOL_NOT_VOTED_DIST" 2> /dev/null)

    POOL_NOCONF_TOTAL=$(jq -re '[.[] | select(.[2] == "drep-alwaysNoConfidence") | .[1]] | add  // 0' \
      <<< "$POOL_NOT_VOTED_DIST" 2> /dev/null)

    case "$ACTION_TAG" in
      # Apply the `defaultAlwaysNoConfidence` to the yes bucket ad note that
      # `defaultAlwaysAbstain` is not used.
      "NoConfidence")
        POOL_PCT=$(bc <<< "scale=2; 100.00 * ($POOL_STAKE_YES + $POOL_NOCONF_TOTAL) / ($POOL_NOT_VOTED_TOTAL + $POOL_NOCONF_TOTAL + $POOL_STAKE_YES + $POOL_STAKE_NO)" 2> /dev/null)
        POOL_TOTAL=$(bc <<< "$POOL_NOT_VOTED_TOTAL + $POOL_NOCONF_TOTAL + $POOL_STAKE_YES + $POOL_STAKE_NO" 2> /dev/null)
        ;;

      # The `defaultAlwaysAbstain` excludes that stake from the voting bucket
      # so we can simply take the totalStake minus the actively voted abstain
      # stake.
      "HardForkInitiation")
        POOL_PCT=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_YES / ($POOL_STAKE_TOTAL - $POOL_STAKE_ABSTAIN)" 2> /dev/null)
        POOL_TOTAL=$(bc <<< "$POOL_STAKE_TOTAL - $POOL_STAKE_ABSTAIN" 2> /dev/null)
        ;;

      # Rest of the actions
      *)
        POOL_PCT=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_YES / ($POOL_NOT_VOTED_TOTAL + $POOL_NOCONF_TOTAL + $POOL_STAKE_YES + $POOL_STAKE_NO)" 2> /dev/null)
        POOL_TOTAL=$(bc <<< "$POOL_NOT_VOTED_TOTAL + $POOL_NOCONF_TOTAL + $POOL_STAKE_YES + $POOL_STAKE_NO" 2> /dev/null)
        ;;
    esac
    [ "$POOL_PCT" == "" ] && POOL_PCT="0"

    # Generate lists with the committee hashes that are voted yes, no or abstain.
    {
      read -r COMMITTEE_HASH_YES
      read -r COMMITTEE_HASH_NO
      read -r COMMITTEE_HASH_ABSTAIN
    } <<< "$(jq -re '
      "\(.committeeVotes | with_entries(select(.value | contains("Yes"))) | keys )",
      "\(.committeeVotes | with_entries(select(.value | contains("No"))) | keys )",
      "\(.committeeVotes | with_entries(select(.value | contains("Abstain"))) | keys)"
    ' <<< "$ACTION" 2> /dev/null)"

    # Calculate the total power of the yes, no and abstain keys
    {
      read -r COMMITTEE_YES
      read -r COMMITTEE_NO
      read -r COMMITTEE_ABSTAIN
    } <<< "$(jq -re "
      ([ .[] | select(.[0]==${COMMITTEE_HASH_YES}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${COMMITTEE_HASH_NO}[]) | .[1] ] | add) // 0,
      ([ .[] | select(.[0]==${COMMITTEE_HASH_ABSTAIN}[]) | .[1] ] | add) // 0
    " <<< "$COMMITTEE_DIST" 2> /dev/null)"

    # Calculate the percentage for the committee
    if [ $((COMMITTEE_TOTAL - COMMITTEE_ABSTAIN)) -eq 0 ]; then
      COMMITTEE_PCT="0"
      COMMITTEE_TOTAL="0"

    else
      COMMITTEE_PCT=$(bc <<< "scale=2; (100.00 * $COMMITTEE_YES) / ($COMMITTEE_TOTAL - $COMMITTEE_ABSTAIN)")
      COMMITTEE_TOTAL=$(bc <<< "$COMMITTEE_TOTAL - $COMMITTEE_ABSTAIN")
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
      } <<< "$(jq -re '
        .txId // "-",
        .govActionIx // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      echo -e "Action-Content:$CYAN Information$OFF"
      echo

      DREP_STAKE_THRESHOLD="n/a"
      DREP_THRESHOLD_TOTAL="n/a"
      POOL_STAKE_THRESHOLD="n/a"
      POOL_THRESHOLD_TOTAL="n/a"
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
      } <<< "$(jq -re '
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
      } <<< "$(jq -re '
        .dRepVotingThresholds.hardForkInitiation // 0,
        .poolVotingThresholds.hardForkInitiation // 0
      ' <<< "$PPARAMS" 2> /dev/null)"

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      DREP_THRESHOLD_TOTAL=$(bc <<< "$DREP_STAKE_THRESHOLD * $DREP_TOTAL / 100")
      if [ "$PROT_MAJOR_VER" -ge 10 ]; then
        THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"
      fi

      POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
      POOL_THRESHOLD_TOTAL=$(bc <<< "$POOL_STAKE_THRESHOLD * $POOL_TOTAL / 100")
      THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"

      THRESHOLD_CHECK "COMMITTEE" "$COMMITTEE_PCT" "$COMMITTEE_THRESHOLD"
    ;;

    "ParameterChange")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
        read -r CHANGE_PARAMETERS
      } <<< "$(jq -re '
        .[0].txId // "-",
        .[0].govActionIx // "-",
        "\(.[1])" // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$GREEN" "Change protocol parameters"
      CHANGE_PARAMETERS_RENDER=$(jq -re "to_entries[] | \"Change parameter $GREEN\(.key)$OFF ► $BLUE\(.value)$OFF\"" <<< "$CHANGE_PARAMETERS" 2> /dev/null)
      echo -e "$CHANGE_PARAMETERS_RENDER"
      echo

      DREP_STAKE_THRESHOLD="0"
      case "${CHANGE_PARAMETERS}" in
        # Security group - SPOs must vote, see:
        #   https://github.com/cardano-foundation/CIPs/tree/master/CIP-1694#protocol-parameter-groups
        *"maxBlockBodySize"*|*"maxTxSize"*|*"maxBlockHeaderSize"*|*"maxValueSize"*|*"maxBlockExecutionUnits"*|*"txFeePerByte"*|*"txFeeFixed"*|*"utxoCostPerByte"*|*"govActionDeposit"*|*"minFeeRefScriptCostPerByte"*)
          POOL_STAKE_THRESHOLD=$(jq -re '.poolVotingThresholds.ppSecurityGroup // 0' <<< "${PPARAMS}" 2> /dev/null)
          POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
          POOL_THRESHOLD_TOTAL=$(bc <<< "$POOL_STAKE_THRESHOLD * $POOL_TOTAL / 100")
          THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"
          echo -e "A parameter from the ${GREEN}SECURITY$OFF group is present ► ${BLUE}StakePools must vote$OFF"
          ;;&

        # Network group
        *"maxBlockBodySize"*|*"maxTxSize"*|*"maxBlockHeaderSize"*|*"maxValueSize"*|*"maxTxExecutionUnits"*|*"maxBlockExecutionUnits"*|*"maxCollateralInputs"*)
          DREP_STAKE_THRESHOLD=$(jq -re "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppNetworkGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}NETWORK$OFF group"
          ;;&

        # Economic group
        *"txFeePerByte"*|*"txFeeFixed"*|*"stakeAddressDeposit"*|*"stakePoolDeposit"*|*"monetaryExpansion"*|*"treasuryCut"*|*"minPoolCost"*|*"utxoCostPerByte"*|*"executionUnitPrices"*)
          DREP_STAKE_THRESHOLD=$(jq -re "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppEconomicGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}ECONOMIC$OFF group"
          ;;&

        # Technical group
        *"poolPledgeInfluence"*|*"poolRetireMaxEpoch"*|*"stakePoolTargetNum"*|*"costModels"*|*"collateralPercentage"*)
          DREP_STAKE_THRESHOLD=$(jq -re "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppTechnicalGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}TECHNICAL$OFF group"
          ;;&

        # Governance group
        *"govActionLifetime"*|*"govActionDeposit"*|*"dRepDeposit"*|*"dRepActivity"*|*"committeeMinSize"*|*"committeeMaxTermLength"*|*"VotingThresholds"*)
          DREP_STAKE_THRESHOLD=$(jq -re "[ $DREP_STAKE_THRESHOLD, .dRepVotingThresholds.ppGovGroup // 0 ] | max" <<< "$PPARAMS" 2> /dev/null)
          echo -e "Parameter changes are included from the ${GREEN}GOVERNANCE$OFF group"
          ;;
      esac
      echo

      if [ "$DREP_STAKE_THRESHOLD" == "0" ] || [ "$DREP_STAKE_THRESHOLD" == "" ]; then
        echo -e "${RED}ERROR - Something went wrong finding the drep stake threshold.$OFF"
        exit 1
      fi

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      DREP_THRESHOLD_TOTAL=$(bc <<< "$DREP_STAKE_THRESHOLD * $DREP_TOTAL / 100")
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
      } <<< "$(jq -re '
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

      DREP_STAKE_THRESHOLD=$(jq -re '.dRepVotingThresholds.updateToConstitution // 0' <<< "$PPARAMS" 2> /dev/null)
      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      DREP_THRESHOLD_TOTAL=$(bc <<< "$DREP_STAKE_THRESHOLD * $DREP_TOTAL / 100")
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
      } <<< "$(jq -re '
        .[0].txId // "-",
        .[0].govActionIx // "-",
        "\(.[1])" // "[]",
        "\(.[2])" // "[]",
        "\(.[3])" // "-"
      ' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$GREEN" "Threshold ->"

      COMMITTEE_KEY_HASHES_ADD=$(jq -re "keys" <<< "$COMMITTEE_KEY_HASHES_ADD" 2> /dev/null)
      COMMITTEE_KEY_HASHES_REMOVE=$(jq -re "[.[].keyHash]" <<< "$COMMITTEE_KEY_HASHES_REMOVE" 2> /dev/null)
      COMMITTEE_THRESHOLD_TYPE=$(jq -re "type" <<< "$COMMITTEE_THRESHOLD" 2> /dev/null)

      case "$COMMITTEE_THRESHOLD_TYPE" in
        "object")
          {
            read -r NUMERATOR
            read -r DENOMINATOR
          } <<< "$(jq -re '.numerator // "-", .denominator // "-"' <<< "$COMMITTEE_THRESHOLD")"
          COMMITTEE_THRESHOLD=$(bc <<< "scale=0; ($NUMERATOR * 100 / $DENOMINATOR) / 1")
          echo -e "Approval of a governance measure requires $NUMERATOR out of $DENOMINATOR ($COMMITTEE_THRESHOLD%) of the votes of committee members.$OFF\n"
          ;;

        "number")
          COMMITTEE_THRESHOLD=$(bc <<< "scale=0; $COMMITTEE_THRESHOLD * 100")
          echo -e "Approval of a governance measure requires $COMMITTEE_THRESHOLD% of the votes of committee members.$OFF\n"
          ;;
      esac

      ADD_HASHES_RENDER=$(jq -re "
        .[2] // {}
          | to_entries as \$entries
          | if (\$entries | length) > 0
            then []
              | \"Adding $GREEN\(.key)-\(.value)\"
              | split(\"-\")
              | \"\(.[0])$OFF ► $BLUE\(.[1])$OFF (max term epoch \(.[2]))\"
            else \"No additions\"
            end
      " <<< "$ACTION_CONTENTS" 2> /dev/null)

      REM_HASHES_RENDER=$(jq -re "
        .[1][] // []
          | to_entries as \$entries
          | if (\$entries | length > 0)
            then \$entries[]
              | \"Remove $GREEN\(.key)$OFF ◄ $RED\(.value)$OFF\"
            else \"No removals\"
            end
      " <<< "$ACTION_CONTENTS" 2> /dev/null)

      echo -e "$ADD_HASHES_RENDER"
      echo -e "$REM_HASHES_RENDER"

      {
        read -r DREP_STAKE_THRESHOLD
        read -r POOL_STAKE_THRESHOLD
      } <<< "$(jq -re '.dRepVotingThresholds.committeeNormal // 0, .poolVotingThresholds.committeeNormal // 0' <<< "$PPARAMS" 2> /dev/null)"

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      DREP_THRESHOLD_TOTAL=$(bc <<< "$DREP_STAKE_THRESHOLD * $DREP_TOTAL / 100")
      THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"

      POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
      POOL_THRESHOLD_TOTAL=$(bc <<< "$POOL_STAKE_THRESHOLD * $POOL_TOTAL / 100")
      THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"

      COMMITTEE_ACCEPT_ICON="";
      ;;

    "NoConfidence")
      {
        read -r PREV_ACTION_UTXO
        read -r PREV_ACTION_IDX
      } <<< "$(jq -re '.txId // "-", .govActionIx // "-"' 2> /dev/null <<< "$ACTION_CONTENTS")"

      PREV_ACTION "$PREV_ACTION_UTXO" "$PREV_ACTION_IDX"
      ACTION_CONTENT "$RED" "No confidence in the committee"

      {
        read -r DREP_STAKE_THRESHOLD
        read -r POOL_STAKE_THRESHOLD
      } <<< "$(jq -re '
        .dRepVotingThresholds.committeeNoConfidence // 0,
        .poolVotingThresholds.committeeNoConfidence // 0
      ' <<< "$PPARAMS" 2> /dev/null)"

      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      DREP_THRESHOLD_TOTAL=$(bc <<< "$DREP_STAKE_THRESHOLD * $DREP_TOTAL / 100")
      THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"

      POOL_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $POOL_STAKE_THRESHOLD")
      POOL_THRESHOLD_TOTAL=$(bc <<< "$POOL_STAKE_THRESHOLD * $POOL_TOTAL / 100")
      THRESHOLD_CHECK "POOL" "$POOL_PCT" "$POOL_STAKE_THRESHOLD"

      COMMITTEE_ACCEPT_ICON=""
      ;;

    "TreasuryWithdrawals")
      {
        read -r WITHDRAWALS_AMOUNT
        read -r WITHDRAWALS_KEY_TYPE
        read -r WITHDRAWALS_HASH
        read -r WITHDRAWALS_NETWORK
      } <<< "$(jq -re '
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

      DREP_STAKE_THRESHOLD=$(jq -re '.dRepVotingThresholds.treasuryWithdrawal // 0' <<< "$PPARAMS" 2> /dev/null)
      DREP_STAKE_THRESHOLD=$(bc <<< "scale=2; 100.00 * $DREP_STAKE_THRESHOLD")
      DREP_THRESHOLD_TOTAL=$(bc <<< "$DREP_STAKE_THRESHOLD * $DREP_TOTAL / 100")
      if [ "$PROT_MAJOR_VER" -ge 10 ]; then
        THRESHOLD_CHECK "DREP" "$DREP_PCT" "$DREP_STAKE_THRESHOLD"
      fi

      POOL_ACCEPT_ICON=""

      THRESHOLD_CHECK "COMMITTEE" "$COMMITTEE_PCT" "$COMMITTEE_THRESHOLD"
      ;;
  esac

  # Expand bash arrays with no IFS space
  NO_SPACE_EXP() {
    local IFS=
    echo "$*"
  }

  # Print a human readable ADA value and unit
  LOVELACE_TO_READABLE() {
    local LOVELACE="$1"
    local READABLE=""

    DIGITS="${#LOVELACE}"
    if [ "$DIGITS" -gt "15" ]; then
      READABLE="$(bc <<< "scale=3; $LOVELACE / 10^15") B₳"
    elif [ "$DIGITS" -gt "12" ]; then
      READABLE="$(bc <<< "scale=3; $LOVELACE / 10^12") M₳"
    elif [ "$DIGITS" -gt "9" ]; then
      READABLE="$(bc <<< "scale=3; $LOVELACE / 10^9") k₳"
    elif [ "$DIGITS" -gt "6" ]; then
      READABLE="$(bc <<< "scale=3; $LOVELACE / 10^6") ₳"
    elif [ "$DIGITS" -gt "3" ]; then
      READABLE="$(bc <<< "scale=3; $LOVELACE / 10^3") m₳"
    else
      READABLE="0.000 ₳"
    fi
    echo -n "$READABLE"
  }

  OUTPUT='Current Votes,"Yes","No","Abstain","Always\nNoConf","Threshold\n(%)","Live\n(%)",Accept'

  if [ "$DREP_ACCEPT_ICON" != "" ]; then
    TMP_ARRAY=(
      "Dreps,"
      "\"$GREEN$ACTION_DREP_VOTE_YES_COUNT @\n$(LOVELACE_TO_READABLE $DREP_STAKE_YES)$OFF\","
      "\"$RED$ACTION_DREP_VOTE_NO_COUNT @\n$(LOVELACE_TO_READABLE $DREP_STAKE_NO)$OFF\","
      "\"$GRAY$ACTION_DREP_ABSTAIN_COUNT @\n$(LOVELACE_TO_READABLE $DREP_STAKE_ABSTAIN)$OFF\","
      "\"$GRAY$DREP_NOCONF_COUNT @\n$(LOVELACE_TO_READABLE $DREP_NOCONF_TOTAL)$OFF\","
      "\"$DREP_STAKE_THRESHOLD% is\n$(LOVELACE_TO_READABLE $DREP_THRESHOLD_TOTAL)\","
      "\"$DREP_PCT% of\n$(LOVELACE_TO_READABLE $DREP_TOTAL)\","
      "$DREP_ACCEPT_ICON"
    )
    DREP_SUMMARY=$(NO_SPACE_EXP "${TMP_ARRAY[@]}")
  else
    DREP_SUMMARY="Dreps,-,-,-,-,-,-,"
  fi

  if [ "$POOL_ACCEPT_ICON" != "" ]; then
    TMP_ARRAY=(
      "StakePools,"
      "\"$GREEN$ACTION_POOL_VOTE_YES_COUNT @\n$(LOVELACE_TO_READABLE $POOL_STAKE_YES)$OFF\","
      "\"$RED$ACTION_POOL_VOTE_NO_COUNT @\n$(LOVELACE_TO_READABLE $POOL_STAKE_NO)$OFF\","
      "\"$GRAY$ACTION_POOL_ABSTAIN_COUNT @\n$(LOVELACE_TO_READABLE $POOL_STAKE_ABSTAIN)$OFF\","
      "\"$GRAY$POOL_NOCONF_COUNT @\n$(LOVELACE_TO_READABLE $POOL_NOCONF_TOTAL)$OFF\","
      "\"$POOL_STAKE_THRESHOLD% is\n$(LOVELACE_TO_READABLE $POOL_THRESHOLD_TOTAL)\","
      "\"$POOL_PCT% of\n$(LOVELACE_TO_READABLE $POOL_TOTAL)\","
      "$POOL_ACCEPT_ICON"
    )
    POOL_SUMMARY=$(NO_SPACE_EXP "${TMP_ARRAY[@]}")
  else
    POOL_SUMMARY="StakePools,-,-,-,-,-,-,"
  fi

  if [ "$COMMITTEE_ACCEPT_ICON" != "" ]; then
    TMP_ARRAY=(
      "Committee,"
      "$GREEN$ACTION_COMMITTEE_VOTE_YES_COUNT$OFF,"
      "$RED$ACTION_COMMITTEE_VOTE_NO_COUNT$OFF,"
      "$GRAY$ACTION_COMMITTEE_ABSTAIN_COUNT$OFF,"
      '"",'
      "\"$COMMITTEE_THRESHOLD% is\n$COMMITTEE_THRESHOLD_TOTAL\","
      "\"$COMMITTEE_PCT% of\n$COMMITTEE_TOTAL\","
      "$COMMITTEE_ACCEPT_ICON"
    )
    COMMITTEE_SUMMARY=$(NO_SPACE_EXP "${TMP_ARRAY[@]}")
  else
    COMMITTEE_SUMMARY="Committee,-,-,-,-,-,-,"
  fi

  echo -e "$OUTPUT\n$DREP_SUMMARY\n$POOL_SUMMARY\n$COMMITTEE_SUMMARY" | nu --stdin -c "\$in | from csv --separator ',' | table --theme thin"

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

  if ! [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^demo$ ]]; then
    echo "Error: only node environments for mainnet, preprod and preview and demo are supported"
    exit 1
  fi

  just set-default-cardano-env {{ENV}} "$MAGIC" "$PPID"
  export CARDANO_NODE_NETWORK_ID="$MAGIC"
  export TESTNET_MAGIC="$MAGIC"
  echo

  [ -n "${DEBUG:-}" ] && set -x

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
  elif [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$ ]]; then
    CARDANO_CLI="cardano-cli"
  fi

  STATE_BEFORE=$(eval "$CARDANO_CLI" latest query gov-state)
  ACTION_BEFORE=$(
    jq -re \
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

  TX_SELECTED=$(jq -re '.
    | to_entries
    | map(select((.value.value | length == 1) and .value.value.lovelace > 5000000))
    | sort_by(.value.value.lovelace)[0]' <<< "$RICH_UTXOS"
  )

  TXIN=$(jq -re '.key' <<< "$TX_SELECTED")
  TXVALUE=$(jq -re '.value.value.lovelace' <<< "$TX_SELECTED")

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
    jq -re \
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
