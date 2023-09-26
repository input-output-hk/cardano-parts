{localFlake}: {flake-parts-lib, ...}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      lib,
      ...
    }: let
      inherit (pkgs) writeShellApplication;
      inherit (cfgPkgs) cardano-address;

      cfgPkgs = config.cardano-parts.pkgs;
      stdPkgs = with pkgs; [age coreutils fd jq moreutils sops];

      secretsFns = ''
        function decrypt_check {
          local FILE="$1"

          if [ "''${USE_DECRYPTION:-false}" = "true" ]; then
            echo -n "<(sops --input-type binary --output-type binary --decrypt $FILE)"
          else
            echo -n "$FILE"
          fi
        }

        function encrypt_check {
          local FILE="$1"

          if [ "''${USE_ENCRYPTION:-false}" = "true" ]; then
            sops --input-type binary --output-type binary --encrypt "$FILE" | sponge "$FILE"
          fi
        }

        export -f encrypt_check
      '';

      selectCardanoCli = ''
        # Inputs:
        #   [$UNSTABLE]
        #   [$USE_SHELL_BINS]

        if [ "''${USE_SHELL_BINS:-}" = "true" ]; then
          CARDANO_CLI=("eval" "cardano-cli")
        elif [ "''${UNSTABLE:-}" = "true" ]; then
          CARDANO_CLI=("eval" "${lib.getExe cfgPkgs.cardano-cli-ng}")
        else
          CARDANO_CLI=("eval" "${lib.getExe cfgPkgs.cardano-cli}")
        fi
      '';

      updateProposalTemplate = ''
        # Inputs:
        #   [$DEBUG]
        #   [$ERA]
        #   $KEY_DIR
        #   $NUM_GENESIS_KEYS
        #   $PAYMENT_KEY
        #   $PROPOSAL_ARGS
        #   [$SUBMIT_TX]
        #   $TESTNET_MAGIC
        #   [$UNSTABLE]
        #   [$USE_DECRYPTION]
        #   [$USE_SHELL_BINS]

        CHANGE_ADDRESS=$(
          "''${CARDANO_CLI[@]}" address build \
            --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
            --testnet-magic "$TESTNET_MAGIC"
        )

        TXIN=$(
          "''${CARDANO_CLI[@]}" query utxo \
            --address "$CHANGE_ADDRESS" \
            --testnet-magic "$TESTNET_MAGIC" \
            --out-file /dev/stdout \
          | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
        )

        EPOCH=$(
          "''${CARDANO_CLI[@]}" query tip \
            --testnet-magic "$TESTNET_MAGIC" \
          | jq .epoch
        )

        echo "$TXIN" > /dev/null
        PROPOSAL_KEY_ARGS=()
        SIGNING_ARGS=()

        for ((i=0; i < NUM_GENESIS_KEYS; i++)); do
          PROPOSAL_KEY_ARGS+=("--genesis-verification-key-file" "$(decrypt_check "$KEY_DIR/genesis-keys/shelley.00$i.vkey")")
          SIGNING_ARGS+=("--signing-key-file" "$(decrypt_check "$KEY_DIR/delegate-keys/shelley.00$i.skey")")
        done

        function create_proposal {
          TARGET_EPOCH="$1"

          "''${CARDANO_CLI[@]}" governance create-update-proposal \
            --epoch "$TARGET_EPOCH" \
            "''${PROPOSAL_ARGS[@]}" \
            "''${PROPOSAL_KEY_ARGS[@]}" \
            --out-file update.proposal

          "''${CARDANO_CLI[@]}" transaction build ''${ERA:+$ERA} \
            --tx-in "$TXIN" \
            --change-address "$CHANGE_ADDRESS" \
            --update-proposal-file update.proposal \
            --testnet-magic "$TESTNET_MAGIC" \
            --out-file tx-proposal.txbody

          "''${CARDANO_CLI[@]}" transaction sign \
            --tx-body-file tx-proposal.txbody \
            --out-file tx-proposal.txsigned \
            --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
            "''${SIGNING_ARGS[@]}"
        }

        create_proposal "$EPOCH"

        if [ "''${SUBMIT_TX:-true}" = "true" ]; then
          if ! "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-proposal.txsigned; then
            create_proposal $((EPOCH + 1))
            "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-proposal.txsigned
          fi
        fi
      '';
    in {
      config = {
        packages.job-gen-custom-node-config = writeShellApplication {
          name = "job-gen-custom-node-config";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ENV]
            #   [$GENESIS_DIR]
            #   [$NUM_GENESIS_KEYS]
            #   [$SECURITY_PARAM]
            #   [$SLOT_LENGTH]
            #   [$START_TIME]
            #   [$TEMPLATE_DIR]
            #   [$TESTNET_MAGIC]
            #   [$UNSTABLE]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            export START_TIME=''${START_TIME:-$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now +30 min")}
            export SLOT_LENGTH=''${SLOT_LENGTH:-1000}
            export SECURITY_PARAM=''${SECURITY_PARAM:-36}
            export NUM_GENESIS_KEYS=''${NUM_GENESIS_KEYS:-3}
            export TESTNET_MAGIC=''${TESTNET_MAGIC:-42}
            export GENESIS_DIR=''${GENESIS_DIR:-"./workbench/custom"}

            if [ "''${UNSTABLE_LIB:-}" = "true" ]; then
              export TEMPLATE_DIR=''${TEMPLATE_DIR:-"${localFlake.inputs.iohk-nix-ng}/cardano-lib/testnet-template"}
            else
              export TEMPLATE_DIR=''${TEMPLATE_DIR:-"${localFlake.inputs.iohk-nix}/cardano-lib/testnet-template"}
            fi

            ${secretsFns}
            ${selectCardanoCli}

            ENV="''${ENV:-custom}"

            mkdir -p "$GENESIS_DIR"
            "''${CARDANO_CLI[@]}" genesis create-cardano \
              --genesis-dir "$GENESIS_DIR" \
              --gen-genesis-keys "$NUM_GENESIS_KEYS" \
              --gen-utxo-keys 1 \
              --supply 30000000000000000 \
              --testnet-magic "$TESTNET_MAGIC" \
              --slot-coefficient 0.05 \
              --byron-template "$TEMPLATE_DIR/byron.json" \
              --shelley-template "$TEMPLATE_DIR/shelley.json" \
              --alonzo-template "$TEMPLATE_DIR/alonzo.json" \
              --conway-template "$TEMPLATE_DIR/conway.json" \
              --node-config-template "$TEMPLATE_DIR/config.json" \
              --security-param "$SECURITY_PARAM" \
              --slot-length "$SLOT_LENGTH" \
              --start-time "$START_TIME"

            # TODO remove when genesis generator outputs non-extended-key format
            pushd "$GENESIS_DIR/genesis-keys" &> /dev/null
              for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                mv shelley.00"$i".vkey shelley.00"$i".vkey-ext
                "''${CARDANO_CLI[@]}" key non-extended-key \
                  --extended-verification-key-file shelley.00"$i".vkey-ext \
                  --verification-key-file shelley.00"$i".vkey
              done
            popd &> /dev/null

            pushd "$GENESIS_DIR/delegate-keys" &> /dev/null
              (for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                cat shelley.00"$i".{opcert.json,vrf.skey,kes.skey} | jq -s
              done) | jq -s > bulk.creds.bft.json
              chmod 0600 bulk.creds.bft.json
            popd &> /dev/null

            cp "$TEMPLATE_DIR/topology-empty-p2p.json" "$GENESIS_DIR/topology.json"

            "''${CARDANO_CLI[@]}" address key-gen \
              --signing-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.skey" \
              --verification-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.vkey"

            "''${CARDANO_CLI[@]}" address build \
              --payment-verification-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.vkey" \
              --testnet-magic "$TESTNET_MAGIC" \
              > "$GENESIS_DIR/utxo-keys/rich-utxo.addr"
              chmod 0600 "$GENESIS_DIR/utxo-keys/rich-utxo.addr"

            # Shape the genesis output directory to match secrets layout expected
            # by cardano-parts for environments and groups. This makes for easier
            # import of new environment secrets.
            pushd "$GENESIS_DIR" &> /dev/null
              mkdir -p envs/"$ENV" rundir
              mv delegate-keys envs/"$ENV"/
              mv genesis-keys envs/"$ENV"/
              mv utxo-keys envs/"$ENV"/
              mv node-config.json ./*-genesis.json topology.json rundir/
            popd &> /dev/null

            fd --type file . "$GENESIS_DIR/envs/$ENV"/ --exec bash -c 'encrypt_check {}'
          '';
        };

        packages.job-create-stake-pool-keys = writeShellApplication {
          name = "job-create-stake-pools";
          runtimeInputs = stdPkgs ++ [cardano-address];
          text = ''
            # Inputs:
            #   [$CURRENT_KES_PERIOD]
            #   [$DEBUG]
            #   [$NO_DEPLOY_DIR]
            #   $POOL_NAMES
            #   $STAKE_POOL_DIR
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            if [ -z "''${POOL_NAMES:-}" ]; then
              echo "Pool names must be provided as a space delimited string via POOL_NAMES env var"
              exit 1
            elif [ -n "''${POOL_NAMES:-}" ]; then
              read -r -a POOLS <<< "$POOL_NAMES"
            fi

            NO_DEPLOY_DIR="''${NO_DEPLOY_DIR:-$STAKE_POOL_DIR/no-deploy}"
            mkdir -p "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"

            # Generate wallet in control of all the funds delegated to the stake pools
            cardano-address recovery-phrase generate > "$STAKE_POOL_DIR"/owner.mnemonic

            # Extract reward address vkey
            cardano-address key from-recovery-phrase Shelley < "$STAKE_POOL_DIR"/owner.mnemonic \
              | cardano-address key child 1852H/1815H/"0"H/2/0 \
              | "''${CARDANO_CLI[@]}" key convert-cardano-address-key --shelley-stake-key \
                --signing-key-file /dev/stdin --out-file /dev/stdout \
              | "''${CARDANO_CLI[@]}" key verification-key --signing-key-file /dev/stdin \
                --verification-key-file /dev/stdout \
              | "''${CARDANO_CLI[@]}" key non-extended-key \
                --extended-verification-key-file /dev/stdin \
                --verification-key-file "$STAKE_POOL_DIR"/reward-stake.vkey

            for ((i=0; i < ''${#POOLS[@]}; i++)); do
              POOL_NAME="''${POOLS[$i]}"
              DEPLOY_FILE="$STAKE_POOL_DIR/deploy/$POOL_NAME"
              NO_DEPLOY_FILE="$NO_DEPLOY_DIR/$POOL_NAME"

              cp "$STAKE_POOL_DIR"/owner.mnemonic "$NO_DEPLOY_FILE"-owner.mnemonic
              cp "$STAKE_POOL_DIR"/reward-stake.vkey "$NO_DEPLOY_FILE"-reward-stake.vkey

              # Extract stake skey/vkey needed for pool registration and delegation
              cardano-address key from-recovery-phrase Shelley < "$NO_DEPLOY_FILE"-owner.mnemonic \
                | cardano-address key child 1852H/1815H/"$((i + 1))"H/2/0 \
                | "''${CARDANO_CLI[@]}" key convert-cardano-address-key --shelley-stake-key \
                  --signing-key-file /dev/stdin \
                  --out-file /dev/stdout \
                | tee "$NO_DEPLOY_FILE"-owner-stake.skey \
                | "''${CARDANO_CLI[@]}" key verification-key \
                  --signing-key-file /dev/stdin \
                  --verification-key-file /dev/stdout \
                | "''${CARDANO_CLI[@]}" key non-extended-key \
                  --extended-verification-key-file /dev/stdin \
                  --verification-key-file "$NO_DEPLOY_FILE"-owner-stake.vkey

              # Generate stake address
              "''${CARDANO_CLI[@]}" stake-address build \
                --stake-verification-key-file "$NO_DEPLOY_FILE"-owner-stake.vkey \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file "$NO_DEPLOY_FILE"-owner-stake.addr

              # Generate cold, vrf and kes keys
              "''${CARDANO_CLI[@]}" node key-gen \
                --cold-signing-key-file "$NO_DEPLOY_FILE"-cold.skey \
                --verification-key-file "$DEPLOY_FILE"-cold.vkey \
                --operational-certificate-issue-counter-file "$NO_DEPLOY_FILE"-cold.counter

              "''${CARDANO_CLI[@]}" node key-gen-VRF \
                --signing-key-file "$DEPLOY_FILE"-vrf.skey \
                --verification-key-file "$DEPLOY_FILE"-vrf.vkey

              "''${CARDANO_CLI[@]}" node key-gen-KES \
                --signing-key-file "$DEPLOY_FILE"-kes.skey \
                --verification-key-file "$DEPLOY_FILE"-kes.vkey

              # Generate stake id
              "''${CARDANO_CLI[@]}" stake-pool id \
                --cold-verification-key-file "$DEPLOY_FILE"-cold.vkey \
                --out-file "$NO_DEPLOY_FILE"-pool.id

              # Generate opcert
              "''${CARDANO_CLI[@]}" node issue-op-cert \
                --kes-period "''${CURRENT_KES_PERIOD:-0}" \
                --kes-verification-key-file "$DEPLOY_FILE"-kes.vkey \
                --operational-certificate-issue-counter-file "$NO_DEPLOY_FILE"-cold.counter \
                --cold-signing-key-file "$NO_DEPLOY_FILE"-cold.skey \
                --out-file "$DEPLOY_FILE".opcert

              # Generate bulk creds file for single pool use
              cat "$DEPLOY_FILE"{.opcert,-vrf.skey,-kes.skey} \
                | jq -s \
                | jq -s \
                > "$DEPLOY_FILE"-bulk.creds
            done

            # Generate bulk creds for all pools in the pool names
            (for ((i=0; i < ''${#POOLS[@]}; i++)); do
              cat "$STAKE_POOL_DIR/deploy/''${POOLS[$i]}"{.opcert,-vrf.skey,-kes.skey} | jq -s
            done) | jq -s > "$NO_DEPLOY_DIR/bulk.creds.pools.json"

            # Adjust secrets permissions and clean up
            chmod 0700 "$STAKE_POOL_DIR" "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"/
            fd --type file . "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"/ --exec chmod 0600
            rm "$STAKE_POOL_DIR"/{owner.mnemonic,reward-stake.vkey}

            fd --type file . "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR" --exec bash -c 'encrypt_check {}'
          '';
        };

        packages.job-register-stake-pools = writeShellApplication {
          name = "job-register-stake-pools";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA]
            #   [$NO_DEPLOY_DIR]
            #   $PAYMENT_KEY
            #   $POOL_NAMES
            #   [$POOL_PLEDGE]
            #   $POOL_RELAY
            #   $POOL_RELAY_PORT
            #   [$STAKE_POOL_DIR]
            #   [$SUBMIT_TX]
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            export STAKE_POOL_DIR=''${STAKE_POOL_DIR:-stake-pools}

            ${secretsFns}
            ${selectCardanoCli}

            if [ -z "''${POOL_NAMES:-}" ]; then
              echo "Pool names must be provided as a space delimited string via POOL_NAMES env var"
              exit 1
            elif [ -n "''${POOL_NAMES:-}" ]; then
              read -r -a POOLS <<< "$POOL_NAMES"
            fi

            if [ -z "''${POOL_PLEDGE:-}" ]; then
              echo "Pool pledge is defaulting to 1 million ADA"
              POOL_PLEDGE="1000000000000"
            fi

            NO_DEPLOY_DIR="''${NO_DEPLOY_DIR:-$STAKE_POOL_DIR/no-deploy}"
            mkdir -p "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"

            NUM_POOLS=$((''${#POOLS[@]}))
            WITNESSES=$((NUM_POOLS * 2 + 1))
            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            for ((i=0; i < NUM_POOLS; i++)); do
              POOL_NAME="''${POOLS[$i]}"
              DEPLOY_FILE="$STAKE_POOL_DIR/deploy/$POOL_NAME"
              NO_DEPLOY_FILE="$NO_DEPLOY_DIR/$POOL_NAME"

              # Generate stake registration and delegation certificate
              "''${CARDANO_CLI[@]}" stake-address registration-certificate \
                --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --out-file "$POOL_NAME"-owner-registration.cert

              "''${CARDANO_CLI[@]}" stake-address delegation-certificate \
                --cold-verification-key-file "$(decrypt_check "$DEPLOY_FILE"-cold.vkey)" \
                --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --out-file "$POOL_NAME"-owner-delegation.cert

              # shellcheck disable=SC2031
              "''${CARDANO_CLI[@]}" stake-pool registration-certificate \
                --testnet-magic "$TESTNET_MAGIC" \
                --cold-verification-key-file "$(decrypt_check "$DEPLOY_FILE"-cold.vkey)" \
                --pool-cost 500000000 \
                --pool-margin 1 \
                --pool-owner-stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --pool-pledge "$POOL_PLEDGE" \
                --single-host-pool-relay "$POOL_RELAY" \
                --pool-relay-port "$POOL_RELAY_PORT" \
                --pool-reward-account-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-reward-stake.vkey)" \
                --vrf-verification-key-file "$(decrypt_check "$DEPLOY_FILE"-vrf.vkey)" \
                --out-file "$POOL_NAME"-registration.cert
            done

            # Generate the reward payment address
            "''${CARDANO_CLI[@]}" address build \
              --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
              --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-reward-stake.vkey)" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file "$NO_DEPLOY_FILE"-reward-payment-stake.addr
            chmod 0600 "$NO_DEPLOY_FILE"-reward-payment-stake.addr
            encrypt_check "$NO_DEPLOY_FILE"-reward-payment-stake.addr

            # Generate transaction
            TXIN=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()

            # Generate arrays needed for build/sign commands
            for ((i=0; i < NUM_POOLS; i++)); do
              POOL_NAME="''${POOLS[$i]}"
              DEPLOY_FILE="$STAKE_POOL_DIR/deploy/$POOL_NAME"
              NO_DEPLOY_FILE="$NO_DEPLOY_DIR/$POOL_NAME"

              STAKE_POOL_ADDR=$(
                "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --testnet-magic "$TESTNET_MAGIC" \
                | tee "$NO_DEPLOY_FILE"-owner-payment-stake.addr
              )
              chmod 0600 "$NO_DEPLOY_FILE"-owner-payment-stake.addr
              encrypt_check "$NO_DEPLOY_FILE"-owner-payment-stake.addr

              BUILD_TX_ARGS+=("--tx-out" "$STAKE_POOL_ADDR+$POOL_PLEDGE")
              BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-owner-registration.cert")
              BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-registration.cert")
              BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-owner-delegation.cert")
              SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-cold.skey")")
              SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-owner-stake.skey")")
            done

            "''${CARDANO_CLI[@]}" transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              "''${BUILD_TX_ARGS[@]}" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-pool-reg.txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-pool-reg.txbody \
              --out-file tx-pool-reg.txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              "''${SIGN_TX_ARGS[@]}"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-pool-reg.txsigned
            fi
          '';
        };

        packages.job-rotate-kes-pools = writeShellApplication {
          name = "job-rotate-kes-pools";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $CURRENT_KES_PERIOD
            #   [$DEBUG]
            #   [$NO_DEPLOY_FILE]
            #   $POOL_NAMES
            #   $STAKE_POOL_DIR
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            if [ -z "''${POOL_NAMES:-}" ]; then
              echo "Pool names must be provided as a space delimited string via POOL_NAMES env var"
              exit 1
            elif [ -n "''${POOL_NAMES:-}" ]; then
              read -r -a POOLS <<< "$POOL_NAMES"
            fi

            NO_DEPLOY_DIR="''${NO_DEPLOY_DIR:-$STAKE_POOL_DIR/no-deploy}"
            mkdir -p "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"

            for ((i=0; i < ''${#POOLS[@]}; i++)); do
              POOL_NAME="''${POOLS[$i]}"
              DEPLOY_FILE="$STAKE_POOL_DIR/deploy/$POOL_NAME"
              NO_DEPLOY_FILE="$NO_DEPLOY_DIR/$POOL_NAME"

              "''${CARDANO_CLI[@]}" node key-gen-KES \
                --signing-key-file "$DEPLOY_FILE"-kes.skey \
                --verification-key-file "$DEPLOY_FILE"-kes.vkey

              "''${CARDANO_CLI[@]}" node issue-op-cert \
                --kes-verification-key-file "$DEPLOY_FILE"-kes.vkey \
                --cold-signing-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.skey)" \
                --operational-certificate-issue-counter-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.counter)" \
                --kes-period "$CURRENT_KES_PERIOD" \
                --out-file "$DEPLOY_FILE".opcert

              encrypt_check "$DEPLOY_FILE"-kes.skey
              encrypt_check "$DEPLOY_FILE"-kes.vkey
              encrypt_check "$DEPLOY_FILE".opcert

              # Generate bulk creds file for single pool use
              (for FILE in "$DEPLOY_FILE"{.opcert,-vrf.skey,-kes.skey}; do
                cat "$(decrypt_check "$FILE")"
              done) \
                | jq -s \
                | jq -s \
                > "$DEPLOY_FILE"-bulk.creds

              encrypt_check "$DEPLOY_FILE"-bulk.creds
            done

            # Generate bulk creds for all pools in the pool names
            (for ((i=0; i < ''${#POOLS[@]}; i++)); do
              (for FILE in "$STAKE_POOL_DIR/deploy/''${POOLS[$i]}"{.opcert,-vrf.skey,-kes.skey}; do
                cat "$(decrypt_check "$FILE")"
              done) | jq -s
            done) | jq -s > "$NO_DEPLOY_DIR/bulk.creds.pools.json"

            encrypt_check "$NO_DEPLOY_DIR/bulk.creds.pools.json"
          '';
        };

        packages.job-move-genesis-utxo = writeShellApplication {
          name = "job-move-genesis-utxo";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $BYRON_SIGNING_KEY
            #   [$DEBUG]
            #   [$ERA]
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            BYRON_UTXO=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --whole-utxo \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq '
                to_entries[]
                | {"txin": .key, "address": .value.address, "amount": .value.value.lovelace}
                | select(.amount > 0)
              '
            )
            FEE=200000
            SUPPLY=$(echo "$BYRON_UTXO" | jq -r '.amount - 200000')
            BYRON_ADDRESS=$(echo "$BYRON_UTXO" | jq -r '.address')
            PAYMENT_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )
            TXIN=$(echo "$BYRON_UTXO" | jq -r '.txin')

            "''${CARDANO_CLI[@]}" transaction build-raw ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --tx-out "$PAYMENT_ADDRESS+$SUPPLY" \
              --fee "$FEE" \
              --out-file tx-byron.txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-byron.txbody \
              --out-file tx-byron.txsigned \
              --address "$BYRON_ADDRESS" \
              --signing-key-file "$(decrypt_check "$BYRON_SIGNING_KEY")"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-byron.txsigned
            fi
          '';
        };

        packages.job-update-proposal-generic = writeShellApplication {
          name = "job-update-proposal-generic";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA]
            #   $KEY_DIR
            #   [$MAJOR_VERSION]
            #   $NUM_GENESIS_KEYS
            #   $PAYMENT_KEY
            #   $PROPOSAL_ARGS[]
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            if [ "$#" -eq 0 ]; then
              echo "Generic update proposal args must be provided as cli args in the pattern:"
              echo "nix run .#job-update-proposal-generic -- \"\''${PROPOSAL_ARGS[@]}\""
              exit 1
            fi
            PROPOSAL_ARGS=("$@")
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-d = writeShellApplication {
          name = "job-update-proposal-d";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   $D_VALUE
            #   [$ERA]
            #   $KEY_DIR
            #   $NUM_GENESIS_KEYS
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            PROPOSAL_ARGS=(
              "--decentralization-parameter" "$D_VALUE"
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-hard-fork = writeShellApplication {
          name = "job-update-proposal-hard-fork";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA]
            #   $KEY_DIR
            #   $MAJOR_VERSION
            #   $NUM_GENESIS_KEYS
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            PROPOSAL_ARGS=(
              "--protocol-major-version" "$MAJOR_VERSION"
              "--protocol-minor-version" "0"
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-cost-model = writeShellApplication {
          name = "job-update-proposal-cost-model";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $COST_MODEL
            #   [$DEBUG]
            #   [$ERA]
            #   $KEY_DIR
            #   $NUM_GENESIS_KEYS
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            PROPOSAL_ARGS=(
              "--cost-model-file" "$COST_MODEL"
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-mainnet-params = writeShellApplication {
          name = "job-update-proposal-mainnet-params";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA]
            #   $KEY_DIR
            #   $NUM_GENESIS_KEYS
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            PROPOSAL_ARGS=(
              "--max-block-body-size" "90112"
              "--number-of-pools" "500"
              "--max-block-execution-units" '(20000000000,62000000)'
              "--max-tx-execution-units" '(10000000000,14000000)'
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-submit-gov-action = writeShellApplication {
          name = "job-submit-gov-action";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $ACTION
            #   [$DEBUG]
            #   [$ERA]
            #   $GOV_ACTION_DEPOSIT
            #   $PAYMENT_KEY
            #   $STAKE_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()

            ERA=''${ERA:+"--conway-era"}
            ACTION=''${ACTION:+"create-constitution"}
            PREV_CONSTITUTION=$("''${CARDANO_CLI[@]}" query constitution-hash --testnet-magic 42)

            WITNESSES=2
            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            # TODO: make work with other actions than constitution
            "''${CARDANO_CLI[@]}" conway governance action "$ACTION" \
              --testnet \
              --stake-verification-key-file "$(decrypt_check "$STAKE_KEY".vkey)" \
              --constitution "\"We the people of Barataria abide by these statutes: 1. Flat Caps are permissible, but cowboy hats are the traditional attire\"" \
              --governance-action-deposit "$GOV_ACTION_DEPOSIT" \
              --out-file "$ACTION".action \
              --proposal-url "https://proposals.sancho.network/1" \
              --anchor-data-hash "FOO" \
              --constitution-url "BAR"

            # Generate transaction
            TXIN=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS+=("--constitution-file" "$ACTION".action)
            SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$STAKE_KEY".skey)")

            "''${CARDANO_CLI[@]}" transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              "''${BUILD_TX_ARGS[@]}" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-"$ACTION".txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-"$ACTION".txbody \
              --out-file tx-"$ACTION".txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              "''${SIGN_TX_ARGS[@]}"

            echo "Previous Constitution hash: $PREV_CONSTITUTION"
            echo "New Constitution hash: TODO"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-"$ACTION".txsigned
            fi
          '';
        };

        packages.job-submit-vote = writeShellApplication {
          name = "job-submit-vote";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $ACTION_TX_ID
            #   [$DEBUG]
            #   $DECISION
            #   [$ERA]
            #   $PAYMENT_KEY
            #   $ROLE
            #   $TESTNET_MAGIC
            #   $VOTE_KEY
            #   [SUBMIT_TX]
            #   VOTE_ARGS[]
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()
            VOTE_ARGS=()

            if [ "$ROLE" == "spo" ]; then
              VOTE_ARGS+=("--cold-verification-key-file" "$(decrypt_check "$VOTE_KEY".vkey)")
            elif [ "$ROLE" == "drep" ]; then
              VOTE_ARGS+=("--drep-verification-key-file" "$(decrypt_check "$VOTE_KEY".vkey)")
            elif [ "$ROLE" == "cc" ]; then
              echo "CC not supported yet"
              exit 1
            else
              echo "ROLE must be one of: spo, drep or cc"
              exit 1
            fi

            if [ "$DECISION" == "yes" ]; then
              VOTE_ARGS+=("--yes")
            elif [ "$DECISION" == "no" ]; then
              VOTE_ARGS+=("--no")
            elif [ "$DECISION" == "abstain" ]; then
              VOTE_ARGS+=("--abstain")
            else
              echo "DECISION must be one of: yes, no or abstain"
              exit 1
            fi
            VOTE_ARGS+=("--governance-action-tx-id" "$ACTION_TX_ID" "--governance-action-index" "0")

            WITNESSES=2
            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )
            # TODO: make work with other actions than constitution
            "''${CARDANO_CLI[@]}" conway governance vote create "''${VOTE_ARGS[@]}" --out-file "$ROLE".vote

            # Generate transaction
            TXIN=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS+=("--vote-file" "$ROLE".vote)
            SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$VOTE_KEY".skey)")

            "''${CARDANO_CLI[@]}" transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              "''${BUILD_TX_ARGS[@]}" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-vote-"$ROLE".txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-vote-"$ROLE".txbody \
              --out-file tx-vote-"$ROLE".txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              "''${SIGN_TX_ARGS[@]}"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-vote-"$ROLE".txsigned
            fi
          '';
        };

        packages.job-register-drep = writeShellApplication {
          name = "job-register-drep";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   $DREP_DIR
            #   [$ERA]
            #   $INDEX
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   $VOTING_POWER
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            mkdir -p "$DREP_DIR"

            "''${CARDANO_CLI[@]}" address key-gen \
              --verification-key-file "$DREP_DIR"/pay-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/pay-"$INDEX".skey

            "''${CARDANO_CLI[@]}" stake-address key-gen \
              --verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/stake-"$INDEX".skey

            "''${CARDANO_CLI[@]}" conway governance drep key-gen \
              --verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/drep-"$INDEX".skey

            DREP_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --testnet-magic "$TESTNET_MAGIC" \
                --payment-verification-key-file "$DREP_DIR"/pay-"$INDEX".vkey \
                --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
                | tee "$DREP_DIR"/drep-"$INDEX".addr
            )

            "''${CARDANO_CLI[@]}" stake-address registration-certificate \
              --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --out-file drep-"$INDEX"-stake.cert

            "''${CARDANO_CLI[@]}" conway governance drep registration-certificate \
              --drep-verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --key-reg-deposit-amt 0 \
              --out-file drep-"$INDEX"-drep.cert

            "''${CARDANO_CLI[@]}" conway governance drep delegation-certificate \
              --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --drep-verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --out-file drep-"$INDEX"-delegation.cert

            WITNESSES=2
            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            # Generate transaction
            TXIN=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
            )

            "''${CARDANO_CLI[@]}" transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --tx-out "$DREP_ADDRESS"+"$VOTING_POWER" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              --testnet-magic "$TESTNET_MAGIC" \
              --certificate drep-"$INDEX"-stake.cert \
              --certificate drep-"$INDEX"-drep.cert \
              --certificate drep-"$INDEX"-delegation.cert \
              --out-file tx-drep-"$INDEX".txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-drep-"$INDEX".txbody \
              --out-file tx-drep-"$INDEX".txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              --signing-key-file "$(decrypt_check "$DREP_DIR"/stake-"$INDEX".skey)"

            fd --type file . "$DREP_DIR"/ --exec bash -c 'encrypt_check {}'

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-drep-"$INDEX".txsigned
            fi
          '';
        };

        packages.job-delegate-drep = writeShellApplication {
          name = "job-delegate-drep";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   $DREP_KEY
            #   [$ERA]
            #   $PAYMENT_KEY
            #   $STAKE_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            "''${CARDANO_CLI[@]}" conway governance drep delegation-certificate \
              --stake-verification-key-file "$(decrypt_check "$STAKE_KEY".vkey)" \
              --drep-verification-key-file "$(decrypt_check "$DREP_KEY".vkey)" \
              --out-file drep-delegation.cert

            WITNESSES=2
            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            # Generate transaction
            TXIN=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
            )

            "''${CARDANO_CLI[@]}" transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              --testnet-magic "$TESTNET_MAGIC" \
              --certificate drep-delegation.cert \
              --out-file tx-drep-delegation.txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-drep-delegation.txbody \
              --out-file tx-drep-delegation.txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              --signing-key-file "$(decrypt_check "$STAKE_KEY".skey)"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-drep-delegation.txsigned
            fi
          '';
        };
      };
    });
  };
}
