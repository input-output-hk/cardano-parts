{localFlake}: {flake-parts-lib, ...}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      ...
    }: let
      inherit (pkgs) writeShellApplication;
      inherit (config.packages) cardano-cli cardano-address;
      updateProposalTemplate = ''
        # Inputs: $PAYMENT_KEY, $NUM_GENESIS_KEYS, $KEY_DIR, $TESTNET_MAGIC, $PROPOSAL_ARGS, $SUBMIT_TX, $ERA, $DEBUG

        CHANGE_ADDRESS=$(
          cardano-cli address build \
            --payment-verification-key-file "$PAYMENT_KEY".vkey \
            --testnet-magic "$TESTNET_MAGIC"
        )

        TXIN=$(
          cardano-cli query utxo \
            --address "$CHANGE_ADDRESS" \
            --testnet-magic "$TESTNET_MAGIC" \
            --out-file /dev/stdout \
          | jq -r 'to_entries[0] | .key'
        )

        EPOCH=$(
          cardano-cli query tip \
            --testnet-magic "$TESTNET_MAGIC" \
          | jq .epoch
        )

        echo "$TXIN" > /dev/null
        PROPOSAL_KEY_ARGS=()
        SIGNING_ARGS=()

        for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
          PROPOSAL_KEY_ARGS+=("--genesis-verification-key-file" "$KEY_DIR/genesis-keys/shelley.00$i.vkey")
          SIGNING_ARGS+=("--signing-key-file" "$KEY_DIR/delegate-keys/shelley.00$i.skey")
        done

        cardano-cli governance create-update-proposal \
          --epoch "$EPOCH" \
          "''${PROPOSAL_ARGS[@]}" \
          "''${PROPOSAL_KEY_ARGS[@]}" \
          --out-file update.proposal

        cardano-cli transaction build ''${ERA:+$ERA} \
          --tx-in "$TXIN" \
          --change-address "$CHANGE_ADDRESS" \
          --update-proposal-file update.proposal \
          --testnet-magic "$TESTNET_MAGIC" \
          --out-file tx-proposal.txbody

        cardano-cli transaction sign \
          --tx-body-file tx-proposal.txbody \
          --out-file tx-proposal.txsigned \
          --signing-key-file "$PAYMENT_KEY".skey \
          "''${SIGNING_ARGS[@]}"

        if [ "''${SUBMIT_TX:-true}" = "true" ]; then
          # TODO: remove if we figure out how to make it detect where in epoch we are
          if ! cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-proposal.txsigned; then
            cardano-cli governance create-update-proposal \
              --epoch $(("$EPOCH" + 1)) \
              "''${PROPOSAL_ARGS[@]}" \
              "''${PROPOSAL_KEY_ARGS[@]}" \
              --out-file update.proposal

            cardano-cli transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --update-proposal-file update.proposal \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-proposal.txbody

            cardano-cli transaction sign \
              --tx-body-file tx-proposal.txbody \
              --out-file tx-proposal.txsigned \
              --signing-key-file "$PAYMENT_KEY".skey \
              "''${SIGNING_ARGS[@]}"

            cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-proposal.txsigned
          fi
        fi
      '';
      # TODO: ignoring this one
      # cabal-project-utils = nixpkgs.callPackages iohk-nix.utils.cabal-project {};
    in {
      config = {
        packages.job-gen-custom-node-config = writeShellApplication {
          name = "job-gen-custom-node-config";
          runtimeInputs = [cardano-cli pkgs.coreutils];
          text = ''
            # Inputs: $START_TIME, $SLOT_LENGTH, $SECURITY_PARAM, $TESTNET_MAGIC, $TEMPLATE_DIR, $GENESIS_DIR, $NUM_GENESIS_KEYS, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            export START_TIME=''${START_TIME:-$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now +30 min")}
            export SLOT_LENGTH=''${SLOT_LENGTH:-1000}
            export SECURITY_PARAM=''${SECURITY_PARAM:-36}
            export NUM_GENESIS_KEYS=''${NUM_GENESIS_KEYS:-3}
            export TESTNET_MAGIC=''${TESTNET_MAGIC:-42}
            export TEMPLATE_DIR=''${TEMPLATE_DIR:-"${localFlake.inputs.iohk-nix}/cardano-lib/testnet-template"}
            export GENESIS_DIR=''${GENESIS_DIR:-"./workbench/custom"}

            mkdir -p "$GENESIS_DIR"
            cardano-cli genesis create-cardano \
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
                cardano-cli key non-extended-key \
                  --extended-verification-key-file shelley.00"$i".vkey-ext \
                  --verification-key-file shelley.00"$i".vkey
              done
            popd &> /dev/null

            pushd "$GENESIS_DIR/delegate-keys" &> /dev/null
              (for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                cat shelley.00"$i".{opcert.json,vrf.skey,kes.skey} | jq -s
              done) > bulk.creds.bft.json
            popd &> /dev/null

            cp "$TEMPLATE_DIR/topology-empty-p2p.json" "$GENESIS_DIR/topology.json"
            cardano-cli address key-gen \
              --signing-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.skey" \
              --verification-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.vkey"
          '';
        };

        packages.job-gen-custom-kv-config =
          writeShellApplication {
            name = "job-gen-custom-kv-config";
            runtimeInputs = [pkgs.jq pkgs.coreutils pkgs.sops];
            text = ''
              # Inputs: $GENESIS_DIR, $NUM_GENESIS_KEYS, $ENV_NAME, $DEBUG
              [ -n "''${DEBUG:-}" ] && set -x

              export GENESIS_DIR=''${GENESIS_DIR:-"./workbench/custom"}
              export NUM_GENESIS_KEYS=''${NUM_GENESIS_KEYS:-3}
              export ENV_NAME=''${ENV_NAME:-"custom-env"}

              mkdir -p "./secrets/cardano/$ENV_NAME"
              pushd "$GENESIS_DIR" &> /dev/null
                jq -n \
                  --arg byron "$(base64 -w 0 < byron-genesis.json)" \
                  --arg shelley "$(base64 -w 0 < shelley-genesis.json)" \
                  --arg alonzo "$(base64 -w 0 < alonzo-genesis.json)" \
                  --arg conway "$(base64 -w 0 < conway-genesis.json)" \
                  --argjson config "$(< node-config.json)" \
                  '{byronGenesisBlob: $byron, shelleyGenesisBlob: $shelley, alonzoGenesisBlob: $alonzo, conwayGenesisBlob: $conway, nodeConfig: $config}' \
                > config.json
                cp config.json "./secrets/cardano/$ENV_NAME.json"

                pushd delegate-keys &> /dev/null
                  for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                    jq -n \
                      --argjson cold "$(<shelley."00$i".skey)" \
                      --argjson vrf "$(<shelley."00$i".vrf.skey)" \
                      --argjson kes "$(<shelley."00$i".kes.skey)" \
                      --argjson opcert "$(<shelley."00$i".opcert.json)" \
                      --argjson counter "$(<shelley."00$i".counter.json)" \
                      --argjson byron_cert "$(<byron."00$i".cert.json)" \
                      '{
                        "kes.skey": $kes,
                        "vrf.skey": $vrf,
                        "opcert.json": $opcert,
                        "byron.cert.json": $byron_cert,
                        "cold.skey": $cold,
                        "cold.counter": $counter
                      }' > "bft-$i.json"
                      cp "bft-$i.json" "./secrets/cardano/$ENV_NAME"
                  done
                popd &> /dev/null

                pushd "./secrets/cardano/$ENV_NAME" &> /dev/null
                  for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                    sops -e "bft-$i.json" > "bft-$i.enc.json" && rm "bft-$i.json"
                  done
                popd &> /dev/null
              popd &> /dev/null
            '';
          }
          // {after = ["gen-custom-node-config"];};

        packages.job-create-stake-pool-keys = writeShellApplication {
          name = "job-create-stake-pools";
          runtimeInputs = [cardano-cli cardano-address pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $NUM_POOLS, $START_INDEX, $STAKE_POOL_DIR, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            END_INDEX=$(("$START_INDEX" + "$NUM_POOLS"))
            mkdir -p "$STAKE_POOL_DIR"

            # Generate wallet in control of all the funds delegated to the stake pools
            cardano-address recovery-phrase generate > "$STAKE_POOL_DIR"/owner.mnemonic

            # Extract reward address vkey
            cardano-address key from-recovery-phrase Shelley < "$STAKE_POOL_DIR"/owner.mnemonic \
              | cardano-address key child 1852H/1815H/"0"H/2/0 \
              | cardano-cli key convert-cardano-address-key --shelley-stake-key \
                --signing-key-file /dev/stdin --out-file /dev/stdout \
              | cardano-cli key verification-key --signing-key-file /dev/stdin \
                --verification-key-file /dev/stdout \
              | cardano-cli key non-extended-key \
                --extended-verification-key-file /dev/stdin \
                --verification-key-file "$STAKE_POOL_DIR"/sp-0-reward-stake.vkey

            for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
              # Extract stake skey/vkey needed for pool registration and delegation
              cardano-address key from-recovery-phrase Shelley < "$STAKE_POOL_DIR"/owner.mnemonic \
                | cardano-address key child 1852H/1815H/"$i"H/2/0 \
                | cardano-cli key convert-cardano-address-key --shelley-stake-key \
                  --signing-key-file /dev/stdin \
                  --out-file /dev/stdout \
                | tee "$STAKE_POOL_DIR"/sp-"$i"-owner-stake.skey \
                | cardano-cli key verification-key \
                  --signing-key-file /dev/stdin \
                  --verification-key-file /dev/stdout \
                | cardano-cli key non-extended-key \
                  --extended-verification-key-file /dev/stdin \
                  --verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-owner-stake.vkey

              # Generate cold, vrf and kes keys
              cardano-cli node key-gen \
                --cold-signing-key-file "$STAKE_POOL_DIR"/sp-"$i"-cold.skey \
                --verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-cold.vkey \
                --operational-certificate-issue-counter-file "$STAKE_POOL_DIR"/sp-"$i"-cold.counter

              cardano-cli node key-gen-VRF \
                --signing-key-file "$STAKE_POOL_DIR"/sp-"$i"-vrf.skey \
                --verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-vrf.vkey

              cardano-cli node key-gen-KES \
                --signing-key-file "$STAKE_POOL_DIR"/sp-"$i"-kes.skey \
                --verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-kes.vkey

              # Generate opcert
              cardano-cli node issue-op-cert \
                --kes-period 0 \
                --kes-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-kes.vkey \
                --operational-certificate-issue-counter-file "$STAKE_POOL_DIR"/sp-"$i"-cold.counter \
                --cold-signing-key-file "$STAKE_POOL_DIR"/sp-"$i"-cold.skey \
                --out-file "$STAKE_POOL_DIR"/sp-"$i".opcert
            done

            (for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
              cat "$STAKE_POOL_DIR"/sp-"$i"{.opcert,-vrf.skey,-kes.skey} | jq -s
            done) > "$STAKE_POOL_DIR"/bulk.creds.pools.json
          '';
        };

        packages.job-register-stake-pools = writeShellApplication {
          name = "job-register-stake-pools";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $NUM_POOLS, $START_INDEX, $STAKE_POOL_DIR, $POOL_PLEDGE, $POOL_RELAY, $POOL_RELAY_PORT, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            export STAKE_POOL_DIR=''${STAKE_POOL_DIR:-stake-pools}

            if [ -z "''${POOL_PLEDGE:-}" ]; then
              echo "Pool pledge is defaulting to 1 million ADA"
              POOL_PLEDGE="1000000000000"
            fi

            WITNESSES=$(("$NUM_POOLS" * 2 + 1))
            END_INDEX=$(("$START_INDEX" + "$NUM_POOLS"))
            CHANGE_ADDRESS=$(
              cardano-cli address build \
                --payment-verification-key-file "$PAYMENT_KEY".vkey \
                --testnet-magic "$TESTNET_MAGIC"
            )

            for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
              # Generate stake registration and delegation certificate
              cardano-cli stake-address registration-certificate \
                --stake-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-owner-stake.vkey \
                --out-file sp-"$i"-owner-registration.cert

              cardano-cli stake-address delegation-certificate \
                --cold-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-cold.vkey \
                --stake-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-owner-stake.vkey \
                --out-file sp-"$i"-owner-delegation.cert

              # shellcheck disable=SC2031
              cardano-cli stake-pool registration-certificate \
                --testnet-magic "$TESTNET_MAGIC" \
                --cold-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-cold.vkey \
                --pool-cost 500000000 \
                --pool-margin 1 \
                --pool-owner-stake-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-owner-stake.vkey \
                --pool-pledge "$POOL_PLEDGE" \
                --single-host-pool-relay "$POOL_RELAY" \
                --pool-relay-port "$POOL_RELAY_PORT" \
                --pool-reward-account-verification-key-file "$STAKE_POOL_DIR"/sp-0-reward-stake.vkey \
                --vrf-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-vrf.vkey \
                --out-file sp-"$i"-registration.cert
            done

            # Generate transaction
            TXIN=$(
              cardano-cli query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r 'to_entries[0] | .key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()

            for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
              BUILD_TX_ARGS+=("--certificate-file" "sp-$i-registration.cert")
              SIGN_TX_ARGS+=("--signing-key-file" "$STAKE_POOL_DIR/sp-$i-cold.skey")
              SIGN_TX_ARGS+=("--signing-key-file" "$STAKE_POOL_DIR/sp-$i-owner-stake.skey")
            done

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()
            for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
              STAKE_POOL_ADDR=$(
                cardano-cli address build \
                --payment-verification-key-file "$PAYMENT_KEY".vkey \
                --stake-verification-key-file "$STAKE_POOL_DIR"/sp-"$i"-owner-stake.vkey \
                --testnet-magic "$TESTNET_MAGIC"
              )
              BUILD_TX_ARGS+=("--tx-out" "$STAKE_POOL_ADDR+$POOL_PLEDGE")
              BUILD_TX_ARGS+=("--certificate-file" "sp-$i-owner-registration.cert")
              BUILD_TX_ARGS+=("--certificate-file" "sp-$i-registration.cert")
              BUILD_TX_ARGS+=("--certificate-file" "sp-$i-owner-delegation.cert")
              SIGN_TX_ARGS+=("--signing-key-file" "$STAKE_POOL_DIR/sp-$i-cold.skey")
              SIGN_TX_ARGS+=("--signing-key-file" "$STAKE_POOL_DIR/sp-$i-owner-stake.skey")
            done

            cardano-cli transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              "''${BUILD_TX_ARGS[@]}" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-pool-reg.txbody

            cardano-cli transaction sign \
              --tx-body-file tx-pool-reg.txbody \
              --out-file tx-pool-reg.txsigned \
              --signing-key-file "$PAYMENT_KEY".skey \
              "''${SIGN_TX_ARGS[@]}"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-pool-reg.txsigned
            fi
          '';
        };

        packages.job-gen-custom-kv-config-pools =
          writeShellApplication {
            name = "job-gen-custom-kv-config-pools";
            runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
            text = ''
              # Inputs: $NUM_POOLS, $START_INDEX, $STAKE_POOL_DIR, $ENV_NAME, $DEBUG
              [ -n "''${DEBUG:-}" ] && set -x

              export ENV_NAME=''${ENV_NAME:-"custom-env"}

              END_INDEX=$(("$START_INDEX" + "$NUM_POOLS"))
              mkdir -p "./secrets/cardano/$ENV_NAME"
              pushd "$STAKE_POOL_DIR" &> /dev/null
                for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
                  jq -n \
                    --argjson cold    "$(< sp-"$i"-cold.skey)" \
                    --argjson vrf     "$(< sp-"$i"-vrf.skey)" \
                    --argjson kes     "$(< sp-"$i"-kes.skey)" \
                    --argjson opcert  "$(< sp-"$i".opcert)" \
                    --argjson counter "$(< sp-"$i"-cold.counter)" \
                    '{
                      "kes.skey": $kes,
                      "vrf.skey": $vrf,
                      "opcert.json": $opcert,
                      "cold.skey": $cold,
                      "cold.counter": $counter
                    }' > "./secrets/cardano/$ENV_NAME/sp-$i.json"
                done
              popd &> /dev/null

              pushd "./secrets/cardano/$ENV_NAME" &> /dev/null
                for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
                  sops -e "sp-$i.json" > "sp-$i.enc.json" && rm "sp-$i.json"
                done
              popd &> /dev/null
            '';
          }
          // {after = ["gen-custom-node-config"];};

        packages.job-rotate-kes-pools =
          writeShellApplication {
            name = "job-rotate-kes-pools";
            runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
            text = ''
              # Inputs: $NUM_POOLS, $START_INDEX, $STAKE_POOL_DIR, $ENV_NAME, $CURRENT_KES_PERIOD, $DEBUG
              [ -n "''${DEBUG:-}" ] && set -x

              export ENV_NAME=''${ENV_NAME:-"custom-env"}
              END_INDEX=$(("$START_INDEX" + "$NUM_POOLS"))
              mkdir -p "./secrets/cardano/$ENV_NAME"
              pushd "$STAKE_POOL_DIR" &> /dev/null
                for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
                  cardano-cli node key-gen-KES \
                    --signing-key-file sp-"$i"-kes.skey \
                    --verification-key-file sp-"$i"-kes.vkey

                  cardano-cli node issue-op-cert \
                    --kes-verification-key-file sp-"$i"-kes.vkey \
                    --cold-signing-key-file sp-"$i"-cold.skey \
                    --operational-certificate-issue-counter-file sp-"$i"-cold.counter \
                    --kes-period "$CURRENT_KES_PERIOD" \
                    --out-file sp-"$i".opcert

                  jq -n \
                    --argjson cold    "$(< sp-"$i"-cold.skey)" \
                    --argjson vrf     "$(< sp-"$i"-vrf.skey)" \
                    --argjson kes     "$(< sp-"$i"-kes.skey)" \
                    --argjson opcert  "$(< sp-"$i".opcert)" \
                    --argjson counter "$(< sp-"$i"-cold.counter)" \
                    '{
                      "kes.skey": $kes,
                      "vrf.skey": $vrf,
                      "opcert.json": $opcert,
                      "cold.skey": $cold,
                      "cold.counter": $counter
                    }' > "./secrets/cardano/$ENV_NAME/sp-$i.json"
                done
              popd &> /dev/null

              pushd "./secrets/cardano/$ENV_NAME" &> /dev/null
                for ((i="$START_INDEX"; i < "$END_INDEX"; i++)); do
                  sops -e "sp-$i.json" > "sp-$i.enc.json" && rm "sp-$i.json"
                done
              popd &> /dev/null
            '';
          }
          // {after = ["gen-custom-node-config"];};

        packages.job-move-genesis-utxo = writeShellApplication {
          name = "job-move-genesis-utxo";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_ADDRESS, $BYRON_SIGNING_KEY, $TESTNET_MAGIC, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            BYRON_UTXO=$(
              cardano-cli query utxo \
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
            TXIN=$(echo "$BYRON_UTXO" | jq -r '.txin')

            cardano-cli transaction build-raw ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --tx-out "$PAYMENT_ADDRESS+$SUPPLY" \
              --fee "$FEE" \
              --out-file tx-byron.txbody

            cardano-cli transaction sign \
              --tx-body-file tx-byron.txbody \
              --out-file tx-byron.txsigned \
              --address "$BYRON_ADDRESS" \
              --signing-key-file "$BYRON_SIGNING_KEY"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-byron.txsigned
            fi
          '';
        };

        packages.job-update-proposal-generic = writeShellApplication {
          name = "job-update-proposal-generic";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $NUM_GENESIS_KEYS, $KEY_DIR, [$MAJOR_VERSION], $TESTNET_MAGIC, $PROPOSAL_ARGS, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

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
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $NUM_GENESIS_KEYS, $KEY_DIR, $D_VALUE, $TESTNET_MAGIC, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            PROPOSAL_ARGS=(
              "--decentralization-parameter" "$D_VALUE"
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-hard-fork = writeShellApplication {
          name = "job-update-proposal-hard-fork";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $NUM_GENESIS_KEYS, $KEY_DIR, $MAJOR_VERSION, $TESTNET_MAGIC, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            PROPOSAL_ARGS=(
              "--protocol-major-version" "$MAJOR_VERSION"
              "--protocol-minor-version" "0"
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-cost-model = writeShellApplication {
          name = "job-update-proposal-cost-model";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $NUM_GENESIS_KEYS, $KEY_DIR, $COST_MODEL, $TESTNET_MAGIC, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

            PROPOSAL_ARGS=(
              "--cost-model-file" "$COST_MODEL"
            )
            ${updateProposalTemplate}
          '';
        };

        packages.job-update-proposal-mainnet-params = writeShellApplication {
          name = "job-update-proposal-mainnet-params";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $NUM_GENESIS_KEYS, $KEY_DIR, $TESTNET_MAGIC, $SUBMIT_TX, $ERA, $DEBUG
            [ -n "''${DEBUG:-}" ] && set -x

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
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $TESTNET_MAGIC, $STAKE_KEY, $ERA, $DEBUG, $GOV_ACTION_DEPOSIT, ACTION_ARGS[]
            [ -n "''${DEBUG:-}" ] && set -x

            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()

            ERA=''${ERA:+"--conway-era"}
            ACTION=''${ACTION:+"create-constitution"}
            PREV_CONSTITUTION=$(cardano-cli query constitution-hash --testnet-magic 42)

            WITNESSES=2
            CHANGE_ADDRESS=$(
              cardano-cli address build \
                --payment-verification-key-file "$PAYMENT_KEY".vkey \
                --testnet-magic "$TESTNET_MAGIC"
            )

            # TODO: make work with other actions than constitution
            cardano-cli conway governance action "$ACTION" \
              --testnet \
              --stake-verification-key-file "$STAKE_KEY".vkey \
              --constitution "We the people of Barataria abide by these statutes: 1. Flat Caps are permissible, but cowboy hats are the traditional atire" \
              --governance-action-deposit "$GOV_ACTION_DEPOSIT" \
              --out-file "$ACTION".action \
              --proposal-url "https://proposals.sancho.network/1" \
              --anchor-data-hash "FOO" \
              --constitution-url "BAR"

            # Generate transaction
            TXIN=$(
              cardano-cli query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r 'to_entries[0] | .key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS+=("--constitution-file" "$ACTION".action)
            SIGN_TX_ARGS+=("--signing-key-file" "$STAKE_KEY".skey)

            cardano-cli transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              "''${BUILD_TX_ARGS[@]}" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-"$ACTION".txbody

            cardano-cli transaction sign \
              --tx-body-file tx-"$ACTION".txbody \
              --out-file tx-"$ACTION".txsigned \
              --signing-key-file "$PAYMENT_KEY".skey \
              "''${SIGN_TX_ARGS[@]}"

            echo "Previous Constitution hash: $PREV_CONSTITUTION"
            echo "New Constitution hash: TODO"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-"$ACTION".txsigned
            fi
          '';
        };

        packages.job-submit-vote = writeShellApplication {
          name = "job-submit-vote";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $VOTE_KEY, $TESTNET_MAGIC, $ACTION_TX_ID, $ROLE, $DECISION, $ERA, $DEBUG, VOTE_ARGS[]
            [ -n "''${DEBUG:-}" ] && set -x

            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()
            VOTE_ARGS=()

            if [ "$ROLE" == "spo" ]; then
              VOTE_ARGS+=("--cold-verification-key-file" "$VOTE_KEY".vkey)
            elif [ "$ROLE" == "drep" ]; then
              VOTE_ARGS+=("--drep-verification-key-file" "$VOTE_KEY".vkey)
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
              cardano-cli address build \
                --payment-verification-key-file "$PAYMENT_KEY".vkey \
                --testnet-magic "$TESTNET_MAGIC"
            )
            # TODO: make work with other actions than constitution
            cardano-cli conway governance vote create "''${VOTE_ARGS[@]}" --out-file "$ROLE".vote

            # Generate transaction
            TXIN=$(
              cardano-cli query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r 'to_entries[0] | .key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS+=("--vote-file" "$ROLE".vote)
            SIGN_TX_ARGS+=("--signing-key-file" "$VOTE_KEY".skey)

            cardano-cli transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              "''${BUILD_TX_ARGS[@]}" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file tx-vote-"$ROLE".txbody

            cardano-cli transaction sign \
              --tx-body-file tx-vote-"$ROLE".txbody \
              --out-file tx-vote-"$ROLE".txsigned \
              --signing-key-file "$PAYMENT_KEY".skey \
              "''${SIGN_TX_ARGS[@]}"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-vote-"$ROLE".txsigned
            fi
          '';
        };

        packages.job-register-drep = writeShellApplication {
          name = "job-register-drep";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $TESTNET_MAGIC, $DREP_DIR, $POOL_KEY $VOTING_POWER, $INDEX, $ERA, $DEBUG,
            [ -n "''${DEBUG:-}" ] && set -x

            mkdir -p "$DREP_DIR"

            cardano-cli address key-gen \
              --verification-key-file "$DREP_DIR"/pay-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/pay-"$INDEX".skey

            cardano-cli stake-address key-gen \
              --verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/stake-"$INDEX".skey

            cardano-cli conway governance drep key-gen \
              --verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/drep-"$INDEX".skey

            DREP_ADDRESS=$(
              cardano-cli address build \
                --testnet-magic "$TESTNET_MAGIC" \
                --payment-verification-key-file "$DREP_DIR"/pay-"$INDEX".vkey \
                --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey
            )

            cardano-cli stake-address registration-certificate \
              --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --out-file drep-"$INDEX"-stake.cert

            cardano-cli conway governance drep registration-certificate \
              --drep-verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --key-reg-deposit-amt 0 \
              --out-file drep-"$INDEX"-drep.cert

            cardano-cli conway governance drep delegation-certificate \
              --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --drep-verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --out-file drep-"$INDEX"-delegation.cert

            WITNESSES=2
            CHANGE_ADDRESS=$(
              cardano-cli address build \
                --payment-verification-key-file "$PAYMENT_KEY".vkey \
                --testnet-magic "$TESTNET_MAGIC"
            )

            # Generate transaction
            TXIN=$(
              cardano-cli query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r 'to_entries[0] | .key'
            )

            cardano-cli transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --tx-out "$DREP_ADDRESS"+"$VOTING_POWER" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              --testnet-magic "$TESTNET_MAGIC" \
              --certificate drep-"$INDEX"-stake.cert \
              --certificate drep-"$INDEX"-drep.cert \
              --certificate drep-"$INDEX"-delegation.cert \
              --out-file tx-drep-"$INDEX".txbody

            cardano-cli transaction sign \
              --tx-body-file tx-drep-"$INDEX".txbody \
              --out-file tx-drep-"$INDEX".txsigned \
              --signing-key-file "$PAYMENT_KEY".skey \
              --signing-key-file "$DREP_DIR"/stake-"$INDEX".skey

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-drep-"$INDEX".txsigned
            fi
          '';
        };

        packages.job-delegate-drep = writeShellApplication {
          name = "job-delegate-drep";
          runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
          text = ''
            # Inputs: $PAYMENT_KEY, $STAKE_KEY, $DREP_KEY, $POOL_KEY, $TESTNET_MAGIC, $ERA, $DEBUG,
            [ -n "''${DEBUG:-}" ] && set -x

            cardano-cli conway governance drep delegation-certificate \
              --stake-verification-key-file "$STAKE_KEY".vkey \
              --drep-verification-key-file "$DREP_KEY".vkey \
              --out-file drep-delegation.cert

            WITNESSES=2
            CHANGE_ADDRESS=$(
              cardano-cli address build \
                --payment-verification-key-file "$PAYMENT_KEY".vkey \
                --testnet-magic "$TESTNET_MAGIC"
            )

            # Generate transaction
            TXIN=$(
              cardano-cli query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r 'to_entries[0] | .key'
            )

            cardano-cli transaction build ''${ERA:+$ERA} \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              --testnet-magic "$TESTNET_MAGIC" \
              --certificate drep-delegation.cert \
              --out-file tx-drep-delegation.txbody

            cardano-cli transaction sign \
              --tx-body-file tx-drep-delegation.txbody \
              --out-file tx-drep-delegation.txsigned \
              --signing-key-file "$PAYMENT_KEY".skey \
              --signing-key-file "$STAKE_KEY".skey

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              cardano-cli transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-drep-delegation.txsigned
            fi
          '';
        };
      };
    });
  };
}
