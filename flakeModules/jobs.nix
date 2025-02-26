{localFlake}: {flake-parts-lib, ...}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      lib,
      system,
      ...
    }: let
      inherit (pkgs) runCommand writeShellApplication;
      inherit (cfgPkgs) cardano-address;
      inherit (opsLib) generateStaticHTMLConfigs;

      cardanoLib = localFlake.cardano-parts.pkgs.special.cardanoLib system;
      cardanoLibNg = localFlake.cardano-parts.pkgs.special.cardanoLibNg system;
      opsLib = localFlake.cardano-parts.lib.opsLib pkgs;

      cfgPkgs = config.cardano-parts.pkgs;
      stdPkgs = with pkgs; [age coreutils fd jq moreutils sops];

      # To support searching for sops config files from the target path rather than cwd up,
      # implement a userland solution until natively sops supported.
      #
      # This enables $NO_DEPLOY_DIR to be separate from the default $STAKE_POOL_DIR/no-deploy default location.
      # Ref: https://github.com/getsops/sops/issues/242#issuecomment-999809670
      secretsFns = ''
        function sops_config {
          # Suppress xtrace on this fn as the return string is observed from the caller's output
          { SHOPTS="$-"; set +x; } 2> /dev/null

          FILE="$1"
          CONFIG_DIR=$(dirname "$(realpath "$FILE")")
          while ! [ -f "$CONFIG_DIR/.sops.yaml" ]; do
            if [ "$CONFIG_DIR" = "/" ]; then
              >&2 echo "error: no .sops.yaml file was found while walking the directory structure upwards from the target file: \"$FILE\""
              exit 1
            fi
            CONFIG_DIR=$(dirname "$CONFIG_DIR")
            done

          echo "$CONFIG_DIR/.sops.yaml"

          # Reset the xtrace option to its state prior to suppression
          [ -n "''${SHOPTS//[^x]/}" ] && set -x
        }

        function decrypt_check {
          local FILE="$1"

          if [ "''${USE_DECRYPTION:-false}" = "true" ]; then
            echo -n "<(sops --config $(sops_config "$FILE") --input-type binary --output-type binary --decrypt $FILE)"
          else
            echo -n "$FILE"
          fi
        }

        function encrypt_check {
          local FILE="$1"

          if [ "''${USE_ENCRYPTION:-false}" = "true" ]; then
            if ! [ -L "$FILE" ]; then
              if ! jq -e 'has("sops") and has("data") and (.data | startswith("ENC["))' &> /dev/null < "$FILE"; then
                echo "encrypting: file $FILE"
                sops --config "$(sops_config "$FILE")" --input-type binary --output-type binary --encrypt "$FILE" | sponge "$FILE"
              else
                echo "warning: file \"$FILE\" appears to already be binary encrypted, skipping"
              fi
            else
              echo "warning: file \"$FILE\" appears to to be a symlink, skipping"
            fi
          fi
        }

        export -f encrypt_check
        export -f sops_config
      '';

      selectCardanoCli = ''
        # Inputs:
        #   [$ERA_CMD]
        #   [$UNSTABLE]
        #   [$USE_SHELL_BINS]

        if [ "''${USE_SHELL_BINS:-}" = "true" ]; then
          CARDANO_CLI_NO_ERA=("eval" "cardano-cli")
        elif [ "''${UNSTABLE:-}" = "true" ]; then
          CARDANO_CLI_NO_ERA=("eval" "${lib.getExe cfgPkgs.cardano-cli-ng}")
        else
          CARDANO_CLI_NO_ERA=("eval" "${lib.getExe cfgPkgs.cardano-cli}")
        fi

        CARDANO_CLI=("''${CARDANO_CLI_NO_ERA[@]}" "''${ERA_CMD:+$ERA_CMD}")
      '';

      updateProposalTemplate = ''
        # Inputs:
        #   [$DEBUG]
        #   [$EPOCH]
        #   [$ERA] (deprecated `--$ERA-era` flag)
        #   [$ERA_CMD]
        #   [$FEE]
        #   $KEY_DIR
        #   $NUM_GENESIS_KEYS
        #   $PAYMENT_KEY
        #   $PROPOSAL_ARGS
        #   [$SUBMIT_TX]
        #   $TESTNET_MAGIC
        #   [$UNSTABLE]
        #   [$USE_DECRYPTION]
        #   [$USE_SHELL_BINS]
        #   [$UTXO]

        if [ -z "''${FEE:-}" ]; then
          echo "Fee for update proposal tx is defaulting to 500000 lovelace"
          FEE="500000"
        fi

        CHANGE_ADDRESS=$(
          "''${CARDANO_CLI[@]}" address build \
            --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
            --testnet-magic "$TESTNET_MAGIC"
        )

        if [ -z "''${UTXO:-}" ]; then
          UTXO=$(
            "''${CARDANO_CLI[@]}" query utxo \
              --address "$CHANGE_ADDRESS" \
              --testnet-magic "$TESTNET_MAGIC" \
              --out-file /dev/stdout \
            | jq -r --arg fee "$FEE" 'to_entries
              |
                [
                  sort_by(.value.value.lovelace)[]
                    | select(.value.value > ($fee | tonumber))
                    | {"txin": .key, "address": .value.address, "amount": .value.value.lovelace}
                ]
              [0]'
          )
        fi

        TXIN=$(jq -r '.txin' <<< "$UTXO")
        TXVAL=$(jq -r '.amount' <<< "$UTXO")
        CHANGE=$((TXVAL - FEE))

        if [ -z "''${EPOCH:-}" ]; then
          EPOCH=$(
            "''${CARDANO_CLI[@]}" query tip \
              --testnet-magic "$TESTNET_MAGIC" \
            | jq .epoch
          )
        fi

        echo "$TXIN" > /dev/null
        PROPOSAL_KEY_ARGS=()
        SIGNING_ARGS=()

        for ((i=0; i < NUM_GENESIS_KEYS; i++)); do
          PROPOSAL_KEY_ARGS+=("--genesis-verification-key-file" "$(decrypt_check "$KEY_DIR/genesis-keys/shelley.00$i.vkey")")
          SIGNING_ARGS+=("--signing-key-file" "$(decrypt_check "$KEY_DIR/delegate-keys/shelley.00$i.skey")")
        done

        function create_proposal {
          TARGET_EPOCH="$1"

          "''${CARDANO_CLI[@]}" governance action create-protocol-parameters-update \
            --epoch "$TARGET_EPOCH" \
            "''${PROPOSAL_ARGS[@]}" \
            "''${PROPOSAL_KEY_ARGS[@]}" \
            --out-file update.proposal

          "''${CARDANO_CLI[@]}" transaction build-raw ''${ERA:+$ERA} \
            --tx-in "$TXIN" \
            --tx-out "$CHANGE_ADDRESS+$CHANGE" \
            --fee "$FEE" \
            --update-proposal-file update.proposal \
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

      envCfgs = cardanoLib: generateStaticHTMLConfigs pkgs cardanoLib cardanoLib.environments;
    in {
      config.packages = {
        job-gen-env-config = let
          configDir = runCommand "configDir" {} ''
            mkdir -p $out
            cp -r ${envCfgs cardanoLib} $out/environments
            cp -r ${envCfgs cardanoLibNg} $out/environments-pre

            chmod +w $out/{environments,environments-pre}/config
          '';
        in
          writeShellApplication {
            name = "job-gen-custom-node-config";
            runtimeInputs = stdPkgs;
            text = ''
              # Inputs:
              #   [$DEBUG]

              [ -n "''${DEBUG:-}" ] && set -x

              ln -sfn ${configDir} result
              echo "Release and pre-release environment configs can be found in result/"
            '';
          };

        job-gen-custom-node-config = writeShellApplication {
          name = "job-gen-custom-node-config";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ENV]
            #   [$ERA_CMD]
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

            # Remove once the cardano-node new tracing is default in nixosModules.
            jq '. += {UseTraceDispatcher: false}' \
              < "$GENESIS_DIR/node-config.json" \
              | sponge "$GENESIS_DIR/node-config.json"

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

        job-gen-custom-node-config-data = writeShellApplication {
          name = "job-gen-custom-node-config-data";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ENV]
            #   [$ERA_CMD]
            #   [$GENESIS_DIR]
            #   [$INITIAL_FUNDS]
            #   [$MAX_SUPPLY]
            #   [$NUM_GENESIS_KEYS]
            #   [$SECURITY_PARAM]
            #   [$SLOT_LENGTH]
            #   [$START_TIME]
            #   [$TEMPLATE_DIR]
            #   [$TESTNET_MAGIC]
            #   [$UNSTABLE]
            #   [$UNSTABLE_LIB]
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
            ACTIVE_SLOTS_COEFF="0.050"
            EPOCH_LENGTH=$(perl -E "say ((10 * $SECURITY_PARAM) / $ACTIVE_SLOTS_COEFF)")
            SLOT_LENGTH_SEC=$(perl -E "say ($SLOT_LENGTH / 1000)")

            if [ -z "''${MAX_SUPPLY:-}" ]; then
              # cardano-cli throws an error if max supply is larger than this
              MAX_SUPPLY="45000000000000000"
            fi

            # Use the new create-testnet-data cli cmd
            mkdir -p "$GENESIS_DIR"
            "''${CARDANO_CLI[@]}" genesis create-testnet-data \
              --genesis-keys "$NUM_GENESIS_KEYS" \
              --utxo-keys 1 \
              --total-supply "$MAX_SUPPLY" \
              --delegated-supply 0 \
              --testnet-magic "$TESTNET_MAGIC" \
              --spec-shelley "$TEMPLATE_DIR/shelley.json" \
              --spec-alonzo "$TEMPLATE_DIR/alonzo.json" \
              --spec-conway "$TEMPLATE_DIR/conway.json" \
              --start-time "$START_TIME" \
              --out-dir "$GENESIS_DIR"

            # Remove when node release is > 10.1.4
            if [ "''${UNSTABLE:-}" != "true" ]; then
              # cardano-cli "$ERA_CMD" genesis create-testnet-data doesn't provide a byron genesis
              # whereas -ng now does
              "''${CARDANO_CLI_NO_ERA[@]}" byron genesis genesis \
                --protocol-magic "$TESTNET_MAGIC" \
                --start-time "$(date +%s -d "$START_TIME")" \
                --k "$SECURITY_PARAM" \
                --n-poor-addresses 0 \
                --n-delegate-addresses "$NUM_GENESIS_KEYS" \
                --total-balance "$MAX_SUPPLY" \
                --delegate-share 0 \
                --avvm-entry-count 0 \
                --avvm-entry-balance 0 \
                --protocol-parameters-file "$TEMPLATE_DIR/byron.json" \
                --genesis-output-dir "$GENESIS_DIR/byron-config"

              # Move the byron genesis into the same dir as shelley, alonzo, conway genesis files
              mv "$GENESIS_DIR/byron-config/genesis.json" "$GENESIS_DIR/byron-genesis.json"
            fi

            # If initial funds is explicitly declared for the rich key, set it here
            if [ -n "''${INITIAL_FUNDS:-}" ]; then
              jq ".initialFunds[.initialFunds | to_entries | sort_by(.value)[-1].key] |= $INITIAL_FUNDS" \
                < "$GENESIS_DIR/shelley-genesis.json" \
                | sponge "$GENESIS_DIR/shelley-genesis.json"
            fi

            # cardano-cli "$ERA_CMD" genesis create-testnet-data doesn't provide args for these
            jq --sort-keys \
              --argjson jsonUpdates "{
                \"activeSlotsCoeff\": $ACTIVE_SLOTS_COEFF,
                \"epochLength\": $EPOCH_LENGTH,
                \"securityParam\": $SECURITY_PARAM,
                \"slotLength\": $SLOT_LENGTH_SEC}" \
              '. += $jsonUpdates' \
              < "$GENESIS_DIR/shelley-genesis.json" \
              | sponge "$GENESIS_DIR/shelley-genesis.json"

            # Obtain a base node config and topology
            cp "$TEMPLATE_DIR/config.json" "$GENESIS_DIR/node-config.json"
            cp "$TEMPLATE_DIR/topology-empty-p2p.json" "$GENESIS_DIR/topology.json"
            chmod +w "$GENESIS_DIR/node-config.json" "$GENESIS_DIR/topology.json"

            # Also prettify the other json files prior to hash calcs
            for i in byron-genesis alonzo-genesis conway-genesis topology; do
              jq --sort-keys < "$GENESIS_DIR/$i.json" | sponge "$GENESIS_DIR/$i.json"
            done

            # Calculate genesis hashes and inject them into the node config file
            HASH_BYRON=$("''${CARDANO_CLI_NO_ERA[@]}" byron genesis print-genesis-hash --genesis-json "$GENESIS_DIR/byron-genesis.json")
            HASH_SHELLEY=$("''${CARDANO_CLI[@]}" genesis hash --genesis "$GENESIS_DIR/shelley-genesis.json")
            HASH_ALONZO=$("''${CARDANO_CLI[@]}" genesis hash --genesis "$GENESIS_DIR/alonzo-genesis.json")
            HASH_CONWAY=$("''${CARDANO_CLI[@]}" genesis hash --genesis "$GENESIS_DIR/conway-genesis.json")
            jq --sort-keys \
              --arg hashByron "$HASH_BYRON" \
              --arg hashShelley "$HASH_SHELLEY" \
              --arg hashAlonzo "$HASH_ALONZO" \
              --arg hashConway "$HASH_CONWAY" \
              '. += {
                ByronGenesisHash: $hashByron,
                ShelleyGenesisHash: $hashShelley,
                AlonzoGenesisHash: $hashAlonzo,
                ConwayGenesisHash: $hashConway,
                UseTraceDispatcher: false
              }' \
              < "$GENESIS_DIR/node-config.json" \
              | sponge "$GENESIS_DIR/node-config.json"

            # Remove unneeded readmes
            fd -e md . "$GENESIS_DIR" -x rm

            # Transform the genesis key subdirs into a create-cardano compatible layout
            pushd "$GENESIS_DIR/genesis-keys" &> /dev/null
              for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                mv "genesis$((i + 1))/key.skey" "shelley.$(printf "%03d" "$i").skey"
                mv "genesis$((i + 1))/key.vkey" "shelley.$(printf "%03d" "$i").vkey"
                rmdir "genesis$((i + 1))/"


                # Remove when node release is > 10.1.4
                if [ "''${UNSTABLE:-}" != "true" ]; then
                  mv ../byron-config/genesis-keys."$(printf "%03d" "$i")".key "byron.$(printf "%03d" "$i").key"
                fi
              done

              # Remove if scope when node release is > 10.1.4
              if [ "''${UNSTABLE:-}" = "true" ]; then
                mv ../byron-gen-command/genesis-keys.000.key byron.000.key
              fi
            popd &> /dev/null

            # Transform the delegate key subdirs into a create-cardano compatible layout
            pushd "$GENESIS_DIR/delegate-keys" &> /dev/null
              for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                mv "delegate$((i + 1))/kes.skey" "shelley.$(printf "%03d" "$i").kes.skey"
                mv "delegate$((i + 1))/kes.vkey" "shelley.$(printf "%03d" "$i").kes.vkey"
                mv "delegate$((i + 1))/key.skey" "shelley.$(printf "%03d" "$i").skey"
                mv "delegate$((i + 1))/key.vkey" "shelley.$(printf "%03d" "$i").vkey"
                mv "delegate$((i + 1))/opcert.cert" "shelley.$(printf "%03d" "$i").opcert.json"
                mv "delegate$((i + 1))/opcert.counter" "shelley.$(printf "%03d" "$i").counter.json"
                mv "delegate$((i + 1))/vrf.skey" "shelley.$(printf "%03d" "$i").vrf.skey"
                mv "delegate$((i + 1))/vrf.vkey" "shelley.$(printf "%03d" "$i").vrf.vkey"
                rmdir "delegate$((i + 1))/"

                # Remove when node release is > 10.1.4
                if [ "''${UNSTABLE:-}" != "true" ]; then
                  mv ../byron-config/delegate-keys."$(printf "%03d" "$i")".key "byron.$(printf "%03d" "$i").key"
                  mv ../byron-config/delegation-cert."$(printf "%03d" "$i")".json "byron.$(printf "%03d" "$i").cert.json"
                fi
              done
              # Remove if scope and first case when node release is > 10.1.4
              if [ "''${UNSTABLE:-}" != "true" ]; then
                rmdir ../byron-config/
              else
                mv ../byron-gen-command/delegate-keys.000.key byron.000.key
                mv ../byron-gen-command/delegation-cert.000.json byron.000.cert.json
                rmdir ../byron-gen-command/
              fi
            popd &> /dev/null

            # Transform the rich key into a create-cardano compatible layout
            mv "$GENESIS_DIR/utxo-keys/utxo1/utxo.skey" "$GENESIS_DIR/utxo-keys/rich-utxo.skey"
            mv "$GENESIS_DIR/utxo-keys/utxo1/utxo.vkey" "$GENESIS_DIR/utxo-keys/rich-utxo.vkey"
            rmdir "$GENESIS_DIR/utxo-keys/utxo1"

            # Determine and save the rich key address
            "''${CARDANO_CLI[@]}" address build \
              --payment-verification-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.vkey" \
              --testnet-magic "$TESTNET_MAGIC" \
              > "$GENESIS_DIR/utxo-keys/rich-utxo.addr"
              chmod 0600 "$GENESIS_DIR/utxo-keys/rich-utxo.addr"

            # Generate a bft bulk credentials file
            pushd "$GENESIS_DIR/delegate-keys" &> /dev/null
              (for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                cat shelley.00"$i".{opcert.json,vrf.skey,kes.skey} | jq -s
              done) | jq -s > bulk.creds.bft.json
              chmod 0600 bulk.creds.bft.json
            popd &> /dev/null

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

        job-gen-custom-node-config-data-ng = writeShellApplication {
          name = "job-gen-custom-node-config-data-ng";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ENV]
            #   [$ERA_CMD]
            #   [$GENESIS_DIR]
            #   [$INITIAL_FUNDS]
            #   [$MAX_SUPPLY]
            #   [$NUM_GENESIS_KEYS]
            #   [$SECURITY_PARAM]
            #   [$SLOT_LENGTH]
            #   [$START_TIME]
            #   [$TEMPLATE_DIR]
            #   [$TESTNET_MAGIC]
            #   [$UNSTABLE]
            #   [$UNSTABLE_LIB]
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
            ACTIVE_SLOTS_COEFF="0.050"
            EPOCH_LENGTH=$(perl -E "say ((10 * $SECURITY_PARAM) / $ACTIVE_SLOTS_COEFF)")
            SLOT_LENGTH_SEC=$(perl -E "say ($SLOT_LENGTH / 1000)")

            # Maintain genesis available funds similar to prior testnets
            INITIAL_FUNDS=''${INITIAL_FUNDS:-30000000000000000}

            # Cardano-cli throws an error above this amount
            MAX_SUPPLY=''${MAX_SUPPLY:-45000000000000000}

            # Bootstrap stakepool delegation. Note that create-testnet-data
            # will only delegate a fraction of this.  However, the difference
            # is irrelevant as we typically retire the bootstrap stakepool
            # once our standard replacement stakepools are spun up.
            DELEGATED_SUPPLY=''${DELEGATED_SUPPLY:-1000000000}

            # Use the new create-testnet-data cli cmd.
            # One pool and delegator are required for the bootstrap pool.
            mkdir -p "$GENESIS_DIR"
            "''${CARDANO_CLI[@]}" genesis create-testnet-data \
              --genesis-keys "$NUM_GENESIS_KEYS" \
              --pools 1 \
              --stake-delegators 1 \
              --utxo-keys 1 \
              --total-supply "$MAX_SUPPLY" \
              --delegated-supply "$DELEGATED_SUPPLY" \
              --testnet-magic "$TESTNET_MAGIC" \
              --spec-shelley "$TEMPLATE_DIR/shelley.json" \
              --spec-alonzo "$TEMPLATE_DIR/alonzo.json" \
              --spec-conway "$TEMPLATE_DIR/conway.json" \
              --start-time "$START_TIME" \
              --out-dir "$GENESIS_DIR"

            # There is no create-testnet-data spec arg for byron yet, and no
            # corresponding byron cli options, so purge the auto-generated
            # non-avvm utxo manually.
            jq --sort-keys \
              '. += {"nonAvvmBalances":{}}' \
              < "$GENESIS_DIR/byron-genesis.json" \
              | sponge "$GENESIS_DIR/byron-genesis.json"

            # Since we remove the byron non-avvm utxo above, we
            # can also delete the corresponding byron delegator key
            # for the bootstrap pool.
            rm -vf "$GENESIS_DIR"/pools-keys/pool1/byron-*

            # Let's also move the bootstrap key files to a more recognizable dir name
            # and also merge the stake-delegators directory here.
            mv "$GENESIS_DIR/pools-keys/pool1" "$GENESIS_DIR/bootstrap-pool"
            mv "$GENESIS_DIR"/stake-delegators/delegator1/* "$GENESIS_DIR/bootstrap-pool/"
            rm -rvf "$GENESIS_DIR/pools-keys" "$GENESIS_DIR/stake-delegators"

            # For reference, create a payment address, stake address and rewards address files
            "''${CARDANO_CLI[@]}" address build \
              --payment-verification-key-file "$GENESIS_DIR/bootstrap-pool/payment.vkey" \
              --staking-verification-key-file "$GENESIS_DIR/bootstrap-pool/staking.vkey" \
              --testnet-magic "$TESTNET_MAGIC" \
            > "$GENESIS_DIR/bootstrap-pool/payment.addr"

            "''${CARDANO_CLI[@]}" stake-address build \
              --staking-verification-key-file "$GENESIS_DIR/bootstrap-pool/staking.vkey" \
              --testnet-magic "$TESTNET_MAGIC" \
            > "$GENESIS_DIR/bootstrap-pool/staking.addr"

            # By default the rewards go to the staking key; this key remains unregistered
            "''${CARDANO_CLI[@]}" stake-address build \
              --staking-verification-key-file "$GENESIS_DIR/bootstrap-pool/staking-reward.vkey" \
              --testnet-magic "$TESTNET_MAGIC" \
            > "$GENESIS_DIR/bootstrap-pool/staking-reward.addr"

            chmod 0600 "$GENESIS_DIR"/bootstrap-pool/*.addr

            # Generate a bootstrap pool bulk credentials file
            pushd "$GENESIS_DIR/bootstrap-pool" &> /dev/null
              cat opcert.cert vrf.skey kes.skey \
                | jq -s \
                | jq -s > bulk.creds.bootstrap.json
              chmod 0600 bulk.creds.bootstrap.json
            popd &> /dev/null

            # Set the initial funds explicitly declared for the rich key
            jq ".initialFunds[.initialFunds | to_entries | sort_by(.value)[-1].key] |= $INITIAL_FUNDS" \
              < "$GENESIS_DIR/shelley-genesis.json" \
              | sponge "$GENESIS_DIR/shelley-genesis.json"

            # cardano-cli "$ERA_CMD" genesis create-testnet-data doesn't provide args for these
            jq --sort-keys \
              --argjson jsonUpdates "{
                \"activeSlotsCoeff\": $ACTIVE_SLOTS_COEFF,
                \"epochLength\": $EPOCH_LENGTH,
                \"securityParam\": $SECURITY_PARAM,
                \"slotLength\": $SLOT_LENGTH_SEC}" \
              '. += $jsonUpdates | .protocolParams.protocolVersion = {"major": 9, "minor": 0}' \
              < "$GENESIS_DIR/shelley-genesis.json" \
              | sponge "$GENESIS_DIR/shelley-genesis.json"

            # Obtain a base node config and topology
            cp "$TEMPLATE_DIR/config.json" "$GENESIS_DIR/node-config.json"
            cp "$TEMPLATE_DIR/topology-empty-p2p.json" "$GENESIS_DIR/topology.json"
            chmod +w "$GENESIS_DIR/node-config.json" "$GENESIS_DIR/topology.json"

            # Set the node config for entering at Conway era
            jq --sort-keys \
              --argjson jsonUpdates '{
                "LastKnownBlockVersion-Major": 9,
                "LastKnownBlockVersion-Minor": 0,
                "LastKnownBlockVersion-Alt": 0,
                "TestAllegraHardForkAtEpoch": 0,
                "TestAlonzoHardForkAtEpoch": 0,
                "TestBabbageHardForkAtEpoch": 0,
                "TestConwayHardForkAtEpoch": 0,
                "TestMaryHardForkAtEpoch": 0,
                "TestShelleyHardForkAtEpoch": 0,
                "UseTraceDispatcher": false}' \
              '. += $jsonUpdates' \
              < "$GENESIS_DIR/node-config.json" \
              | sponge "$GENESIS_DIR/node-config.json"

            # Also prettify the other json files prior to hash calcs
            for i in byron-genesis alonzo-genesis conway-genesis topology; do
              jq --sort-keys < "$GENESIS_DIR/$i.json" | sponge "$GENESIS_DIR/$i.json"
            done

            # Calculate genesis hashes and inject them into the node config file
            HASH_BYRON=$("''${CARDANO_CLI_NO_ERA[@]}" byron genesis print-genesis-hash --genesis-json "$GENESIS_DIR/byron-genesis.json")
            HASH_SHELLEY=$("''${CARDANO_CLI[@]}" genesis hash --genesis "$GENESIS_DIR/shelley-genesis.json")
            HASH_ALONZO=$("''${CARDANO_CLI[@]}" genesis hash --genesis "$GENESIS_DIR/alonzo-genesis.json")
            HASH_CONWAY=$("''${CARDANO_CLI[@]}" genesis hash --genesis "$GENESIS_DIR/conway-genesis.json")
            jq --sort-keys \
              --arg hashByron "$HASH_BYRON" \
              --arg hashShelley "$HASH_SHELLEY" \
              --arg hashAlonzo "$HASH_ALONZO" \
              --arg hashConway "$HASH_CONWAY" \
              '. += {
                ByronGenesisHash: $hashByron,
                ShelleyGenesisHash: $hashShelley,
                AlonzoGenesisHash: $hashAlonzo,
                ConwayGenesisHash: $hashConway
              }' \
              < "$GENESIS_DIR/node-config.json" \
              | sponge "$GENESIS_DIR/node-config.json"

            # Remove unneeded readmes
            fd -e md . "$GENESIS_DIR" -x rm -v

            # Transform the genesis key subdirs into a create-cardano compatible layout
            pushd "$GENESIS_DIR/genesis-keys" &> /dev/null
              for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                mv "genesis$((i + 1))/key.skey" "shelley.$(printf "%03d" "$i").skey"
                mv "genesis$((i + 1))/key.vkey" "shelley.$(printf "%03d" "$i").vkey"
                rmdir -v "genesis$((i + 1))/"
              done

              mv ../byron-gen-command/genesis-keys.000.key byron.000.key
            popd &> /dev/null

            # Transform the delegate key subdirs into a create-cardano compatible layout
            pushd "$GENESIS_DIR/delegate-keys" &> /dev/null
              for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                mv "delegate$((i + 1))/kes.skey" "shelley.$(printf "%03d" "$i").kes.skey"
                mv "delegate$((i + 1))/kes.vkey" "shelley.$(printf "%03d" "$i").kes.vkey"
                mv "delegate$((i + 1))/key.skey" "shelley.$(printf "%03d" "$i").skey"
                mv "delegate$((i + 1))/key.vkey" "shelley.$(printf "%03d" "$i").vkey"
                mv "delegate$((i + 1))/opcert.cert" "shelley.$(printf "%03d" "$i").opcert.json"
                mv "delegate$((i + 1))/opcert.counter" "shelley.$(printf "%03d" "$i").counter.json"
                mv "delegate$((i + 1))/vrf.skey" "shelley.$(printf "%03d" "$i").vrf.skey"
                mv "delegate$((i + 1))/vrf.vkey" "shelley.$(printf "%03d" "$i").vrf.vkey"
                rmdir -v "delegate$((i + 1))/"
              done
            popd &> /dev/null

            # Transform the rich key into a create-cardano compatible layout
            mv "$GENESIS_DIR/utxo-keys/utxo1/utxo.skey" "$GENESIS_DIR/utxo-keys/rich-utxo.skey"
            mv "$GENESIS_DIR/utxo-keys/utxo1/utxo.vkey" "$GENESIS_DIR/utxo-keys/rich-utxo.vkey"
            rmdir -v "$GENESIS_DIR/utxo-keys/utxo1"

            # Determine and save the rich key address
            "''${CARDANO_CLI[@]}" address build \
              --payment-verification-key-file "$GENESIS_DIR/utxo-keys/rich-utxo.vkey" \
              --testnet-magic "$TESTNET_MAGIC" \
              > "$GENESIS_DIR/utxo-keys/rich-utxo.addr"
              chmod 0600 "$GENESIS_DIR/utxo-keys/rich-utxo.addr"

            # Generate a bft bulk credentials file
            pushd "$GENESIS_DIR/delegate-keys" &> /dev/null
              (for ((i=0; i < "$NUM_GENESIS_KEYS"; i++)); do
                cat shelley.00"$i".{opcert.json,vrf.skey,kes.skey} | jq -s
              done) | jq -s > bulk.creds.bft.json
              chmod 0600 bulk.creds.bft.json
            popd &> /dev/null

            # Shape the genesis output directory to match secrets layout expected
            # by cardano-parts for environments and groups. This makes for easier
            # import of new environment secrets.
            pushd "$GENESIS_DIR" &> /dev/null
              mkdir -p envs/"$ENV" rundir
              mv bootstrap-pool envs/"$ENV"/
              mv delegate-keys envs/"$ENV"/
              mv genesis-keys envs/"$ENV"/
              mv utxo-keys envs/"$ENV"/
              mv node-config.json ./*-genesis.json topology.json rundir/
            popd &> /dev/null

            # Clean up remaining files left by create-testnet-data
            rm -vf "$GENESIS_DIR/byron.genesis.spec.json"
            rmdir -v "$GENESIS_DIR/byron-gen-command"

            fd --type file . "$GENESIS_DIR/envs/$ENV"/ --exec bash -c 'encrypt_check {}'
          '';
        };

        job-create-stake-pool-keys = writeShellApplication {
          name = "job-create-stake-pools";
          runtimeInputs = stdPkgs ++ [cardano-address];
          text = ''
            # Inputs:
            #   [$CURRENT_KES_PERIOD]
            #   [$DEBUG]
            #   [$ERA_CMD]
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
              | tee "$STAKE_POOL_DIR"/reward-stake.skey \
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
              cp "$STAKE_POOL_DIR"/reward-stake.skey "$NO_DEPLOY_FILE"-reward-stake.skey
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

              # Generate stake addresses for owner and reward
              "''${CARDANO_CLI[@]}" stake-address build \
                --stake-verification-key-file "$NO_DEPLOY_FILE"-owner-stake.vkey \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file "$NO_DEPLOY_FILE"-owner-stake.addr

              "''${CARDANO_CLI[@]}" stake-address build \
                --stake-verification-key-file "$NO_DEPLOY_FILE"-reward-stake.vkey \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file "$NO_DEPLOY_FILE"-reward-stake.addr

              # Generate cold, vrf and kes keys
              "''${CARDANO_CLI[@]}" node key-gen \
                --cold-signing-key-file "$NO_DEPLOY_FILE"-cold.skey \
                --verification-key-file "$NO_DEPLOY_FILE"-cold.vkey \
                --operational-certificate-issue-counter-file "$NO_DEPLOY_FILE"-cold.counter

              # Block producers require a copy of the cold.vkey for convienence shell aliases.
              cp "$NO_DEPLOY_FILE"-cold.vkey "$DEPLOY_FILE"-cold.vkey

              "''${CARDANO_CLI[@]}" node key-gen-VRF \
                --signing-key-file "$DEPLOY_FILE"-vrf.skey \
                --verification-key-file "$DEPLOY_FILE"-vrf.vkey

              "''${CARDANO_CLI[@]}" node key-gen-KES \
                --signing-key-file "$DEPLOY_FILE"-kes.skey \
                --verification-key-file "$DEPLOY_FILE"-kes.vkey

              # Generate stake id
              "''${CARDANO_CLI[@]}" stake-pool id \
                --cold-verification-key-file "$NO_DEPLOY_FILE"-cold.vkey \
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
            rm "$STAKE_POOL_DIR"/{owner.mnemonic,reward-stake.skey,reward-stake.vkey}

            fd --type file . "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR" --exec bash -c 'encrypt_check {}'
          '';
        };

        job-delegate-rewards-stake-key = writeShellApplication {
          name = "job-delegate-rewards-stake-key";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
            #   [$FEE]
            #   [$NO_DEPLOY_DIR]
            #   $PAYMENT_KEY
            #   [$POOL_DELEG_INDEX]
            #   $POOL_NAMES
            #   [$STAKE_POOL_DIR]
            #   [$SUBMIT_TX]
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]
            #   [$UTXO]

            [ -n "''${DEBUG:-}" ] && set -x

            export STAKE_POOL_DIR=''${STAKE_POOL_DIR:-stake-pools}

            ${secretsFns}
            ${selectCardanoCli}

            if [ -z "''${FEE:-}" ]; then
              echo "Fee for rewards delegation tx is defaulting to 200000 lovelace"
              FEE="200000"
            fi

            if [ -z "''${POOL_NAMES:-}" ]; then
              echo "Pool names must be provided as a space delimited string via POOL_NAMES env var"
              exit 1
            elif [ -n "''${POOL_NAMES:-}" ]; then
              read -r -a POOLS <<< "$POOL_NAMES"
            fi

            POOL_DELEG_INDEX=''${POOL_DELEG_INDEX:-"0"}
            NUM_POOLS=$((''${#POOLS[@]}))
            if ! { [ "$POOL_DELEG_INDEX" -ge "0" ] && [ "$POOL_DELEG_INDEX" -lt "$NUM_POOLS" ]; }; then
              echo "The pool delegation must be the element index of the pool list and defaults to 0"
              exit 1
            fi

            NO_DEPLOY_DIR="''${NO_DEPLOY_DIR:-$STAKE_POOL_DIR/no-deploy}"
            mkdir -p "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"

            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            POOL_NAME="''${POOLS[$POOL_DELEG_INDEX]}"
            NO_DEPLOY_FILE="$NO_DEPLOY_DIR/$POOL_NAME"

            # Generate stake delegation certificate
            if [ -z "''${ERA_CMD:-}" ] || [ "''${ERA_CMD:-}" == "legacy" ]; then
              unset ERA_MOD
            else
              ERA_MOD="stake-"
            fi

            "''${CARDANO_CLI[@]}" stake-address ''${ERA_MOD:+$ERA_MOD}delegation-certificate \
              --cold-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.vkey)" \
              --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-reward-stake.vkey)" \
              --out-file "$POOL_NAME"-reward-delegation.cert

            # Generate transaction
            if [ -z "''${UTXO:-}" ]; then
              UTXO=$(
                "''${CARDANO_CLI[@]}" query utxo \
                  --address "$CHANGE_ADDRESS" \
                  --testnet-magic "$TESTNET_MAGIC" \
                  --out-file /dev/stdout \
                | jq -r --arg fee "$FEE" 'to_entries
                  |
                    [
                      sort_by(.value.value.lovelace)[]
                        | select(.value.value > ($fee | tonumber))
                        | {"txin": .key, "address": .value.address, "amount": .value.value.lovelace}
                    ]
                  [0]'
              )
            fi

            TXIN=$(jq -r '.txin' <<< "$UTXO")
            TXVAL=$(jq -r '.amount' <<< "$UTXO")
            CHANGE=$((TXVAL - FEE))

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS=()
            SIGN_TX_ARGS=()

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-reward-delegation.cert")
            SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-reward-stake.skey")")
            SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-cold.skey")")

            "''${CARDANO_CLI[@]}" transaction build-raw \
              --tx-in "$TXIN" \
              --tx-out "$CHANGE_ADDRESS+$CHANGE" \
              --fee "$FEE" \
              "''${BUILD_TX_ARGS[@]}" \
              --out-file "$POOL_NAME"-tx-pool-deleg.txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file "$POOL_NAME"-tx-pool-deleg.txbody \
              --out-file "$POOL_NAME"-tx-pool-deleg.txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              "''${SIGN_TX_ARGS[@]}"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file "$POOL_NAME"-tx-pool-deleg.txsigned
            fi
          '';
        };

        job-register-stake-pools = writeShellApplication {
          name = "job-register-stake-pools";
          runtimeInputs = stdPkgs ++ [pkgs.curl];
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
            #   [$FEE]
            #   [$NO_DEPLOY_DIR]
            #   $PAYMENT_KEY
            #   [$POOL_METADATA_BASE_URL]
            #   [$POOL_METADATA_URL]
            #   $POOL_NAMES
            #   [$POOL_PLEDGE]
            #   $POOL_RELAY
            #   $POOL_RELAY_PORT
            #   [$STAKE_ADDRESS_DEPOSIT]
            #   [$STAKE_POOL_DEPOSIT]
            #   [$STAKE_POOL_DIR]
            #   [$SUBMIT_TX]
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]
            #   [$UTXO]

            [ -n "''${DEBUG:-}" ] && set -x

            export STAKE_POOL_DIR=''${STAKE_POOL_DIR:-stake-pools}
            METADATA_ARGS=()

            ${secretsFns}
            ${selectCardanoCli}

            if [ -z "''${FEE:-}" ]; then
              echo "Fee for stake pool registration tx is defaulting to 300000 lovelace"
              FEE="300000"
            fi

            if [ -z "''${POOL_NAMES:-}" ]; then
              echo "Pool names must be provided as a space delimited string via POOL_NAMES env var"
              exit 1
            elif [ -n "''${POOL_NAMES:-}" ]; then
              read -r -a POOLS <<< "$POOL_NAMES"
            fi

            if [ -z "''${POOL_PLEDGE:-}" ]; then
              echo "Pool pledge is defaulting to 10 million ADA"
              POOL_PLEDGE="10000000000000"
            fi

            if [ -z "''${STAKE_ADDRESS_DEPOSIT:-}" ]; then
              echo "Stakepool deposit is defaulting to 2000000 lovelace"
              STAKE_ADDRESS_DEPOSIT="2000000"
            fi

            if [ -z "''${STAKE_POOL_DEPOSIT:-}" ]; then
              echo "Stakepool deposit is defaulting to 500000000 lovelace"
              STAKE_POOL_DEPOSIT="500000000"
            fi

            NO_DEPLOY_DIR="''${NO_DEPLOY_DIR:-$STAKE_POOL_DIR/no-deploy}"
            mkdir -p "$STAKE_POOL_DIR"/deploy "$NO_DEPLOY_DIR"

            NUM_POOLS=$((''${#POOLS[@]}))
            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            for ((i=0; i < NUM_POOLS; i++)); do
              POOL_NAME="''${POOLS[$i]}"
              DEPLOY_FILE="$STAKE_POOL_DIR/deploy/$POOL_NAME"
              NO_DEPLOY_FILE="$NO_DEPLOY_DIR/$POOL_NAME"

              if [ -n "''${POOL_METADATA_BASE_URL:-}" ]; then
                POOL_METADATA_URL="$POOL_METADATA_BASE_URL/$POOL_NAME.json"
                POOL_METADATA_HASH=$(curl --silent "$POOL_METADATA_URL"|"''${CARDANO_CLI[@]}" stake-pool metadata-hash --pool-metadata-file /dev/stdin)
                METADATA_ARGS+=("--metadata-url" "$POOL_METADATA_URL" "--metadata-hash" "$POOL_METADATA_HASH")
              elif [ -n "''${POOL_METADATA_URL:-}" ]; then
                POOL_METADATA_HASH=$(curl --silent "$POOL_METADATA_URL"|"''${CARDANO_CLI[@]}" stake-pool metadata-hash --pool-metadata-file /dev/stdin)
                METADATA_ARGS+=("--metadata-url" "$POOL_METADATA_URL" "--metadata-hash" "$POOL_METADATA_HASH")
              fi

              # Generate stake registration and delegation certificate
              if [ "$ERA_CMD" = "conway" ]; then
                eraArgs=("--key-reg-deposit-amt" "$STAKE_ADDRESS_DEPOSIT")
              else
                eraArgs=()
              fi

              "''${CARDANO_CLI[@]}" stake-address registration-certificate \
                --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --out-file "$POOL_NAME"-owner-registration.cert \
                "''${eraArgs[@]}"

              # Include the shared wallet pool rewards registration certificate only once
              if [ "$i" = "0" ]; then
                "''${CARDANO_CLI[@]}" stake-address registration-certificate \
                  --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-reward-stake.vkey)" \
                  --out-file "$POOL_NAME"-reward-registration.cert \
                  "''${eraArgs[@]}"
              fi

              # Generate stake delegation certificate
              if [ -z "''${ERA_CMD:-}" ] || [ "''${ERA_CMD:-}" == "legacy" ]; then
                unset ERA_MOD
              else
                ERA_MOD="stake-"
              fi

              "''${CARDANO_CLI[@]}" stake-address ''${ERA_MOD:+$ERA_MOD}delegation-certificate \
                --cold-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.vkey)" \
                --stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --out-file "$POOL_NAME"-owner-delegation.cert

              "''${CARDANO_CLI[@]}" stake-pool registration-certificate \
                --testnet-magic "$TESTNET_MAGIC" \
                --cold-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.vkey)" \
                --pool-cost 500000000 \
                --pool-margin 1 \
                --pool-owner-stake-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-owner-stake.vkey)" \
                --pool-pledge "$POOL_PLEDGE" \
                --single-host-pool-relay "$POOL_RELAY" \
                --pool-relay-port "$POOL_RELAY_PORT" \
                --pool-reward-account-verification-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-reward-stake.vkey)" \
                --vrf-verification-key-file "$(decrypt_check "$DEPLOY_FILE"-vrf.vkey)" \
                "''${METADATA_ARGS[@]}" \
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
            if [ -z "''${UTXO:-}" ]; then
              UTXO=$(
                "''${CARDANO_CLI[@]}" query utxo \
                  --address "$CHANGE_ADDRESS" \
                  --testnet-magic "$TESTNET_MAGIC" \
                  --out-file /dev/stdout \
                | jq -r --arg fee "$FEE" 'to_entries
                  |
                    [
                      sort_by(.value.value.lovelace)[]
                        | select(.value.value > ($fee | tonumber))
                        | {"txin": .key, "address": .value.address, "amount": .value.value.lovelace}
                    ]
                  [0]'
              )
            fi

            TXIN=$(jq -r '.txin' <<< "$UTXO")
            TXVAL=$(jq -r '.amount' <<< "$UTXO")
            CHANGE=$((TXVAL - (NUM_POOLS * (POOL_PLEDGE + STAKE_POOL_DEPOSIT)) - ((NUM_POOLS + 1) * STAKE_ADDRESS_DEPOSIT) - FEE))

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

              # Include the shared wallet pool rewards registration certificate only once
              if [ "$i" = "0" ]; then
                BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-reward-registration.cert")
                SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-reward-stake.skey")")
              fi

              BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-owner-registration.cert")
              BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-registration.cert")
              BUILD_TX_ARGS+=("--certificate-file" "$POOL_NAME-owner-delegation.cert")
              SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-cold.skey")")
              SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$NO_DEPLOY_FILE-owner-stake.skey")")
            done

            "''${CARDANO_CLI[@]}" transaction build-raw \
              --tx-in "$TXIN" \
              --tx-out "$CHANGE_ADDRESS+$CHANGE" \
              --fee "$FEE" \
              "''${BUILD_TX_ARGS[@]}" \
              --out-file "''${POOLS[0]}"-tx-pool-reg.txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file "''${POOLS[0]}"-tx-pool-reg.txbody \
              --out-file "''${POOLS[0]}"-tx-pool-reg.txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              "''${SIGN_TX_ARGS[@]}"

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file "''${POOLS[0]}"-tx-pool-reg.txsigned
            fi
          '';
        };

        job-retire-bootstrap-pool = writeShellApplication {
          name = "job-retire-bootstrap-pool";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$BOOTSTRAP_POOL_DIR]
            #   [$BOOTSTRAP_POOL_COLD_KEY]
            #   [$BOOTSTRAP_POOL_PAYMENT_KEY]
            #   [$BOOTSTRAP_POOL_STAKING_KEY]
            #   [$EPOCH]
            #   [$ERA_CMD]
            #   [$FEE]
            #   $RICH_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]
            #   [$UTXO]

            [ -n "''${DEBUG:-}" ] && set -x

            EPOCH=''${EPOCH:-1}
            BOOTSTRAP_POOL_DIR=''${BOOTSTRAP_POOL_DIR:-bootstrap-pool}

            [ -z "''${BOOTSTRAP_POOL_COLD_KEY:-}" ] && BOOTSTRAP_POOL_COLD_KEY="$BOOTSTRAP_POOL_DIR/cold"
            [ -z "''${BOOTSTRAP_POOL_PAYMENT_KEY:-}" ] && BOOTSTRAP_POOL_PAYMENT_KEY="$BOOTSTRAP_POOL_DIR/payment"
            [ -z "''${BOOTSTRAP_POOL_STAKING_KEY:-}" ] && BOOTSTRAP_POOL_STAKING_KEY="$BOOTSTRAP_POOL_DIR/staking"

            if [ -z "''${FEE:-}" ]; then
              echo "Fee for retiring the bootstrap pool tx is defaulting to 300000 lovelace"
              FEE="300000"
            fi

            ${secretsFns}
            ${selectCardanoCli}

            # There is only a single shelley delegator UTxO created as part of
            # the job-gen-custom-node-config-data-ng workflow.
            if [ -z "''${UTXO:-}" ]; then
              UTXO=$(
                "''${CARDANO_CLI[@]}" query utxo \
                  --address "$(eval cat "$(decrypt_check "$BOOTSTRAP_POOL_PAYMENT_KEY.addr")")" \
                  --testnet-magic "$TESTNET_MAGIC" \
                  --out-file /dev/stdout \
                | jq -r 'to_entries[]
                  | [{"txin": .key, "address": .value.address, "amount": .value.value.lovelace}][0]'
              )
            fi
            TXIN=$(jq -r '.txin' <<< "$UTXO")
            TXVAL=$(jq -r '.amount' <<< "$UTXO")
            CHANGE=$((TXVAL - FEE))
            CHANGE_ADDRESS=$(eval cat "$(decrypt_check "$RICH_KEY.addr")")

            # Apparently, the genesis-declared delegator stake key cannot be
            # registered, deregistered or have rewards withdrawn, so we
            # simply transfer the existing UTxO associated with the payment
            # address and leave the typically small amount of rewards behind.
            "''${CARDANO_CLI[@]}" stake-pool deregistration-certificate \
              --cold-verification-key-file "$(decrypt_check "$BOOTSTRAP_POOL_COLD_KEY.vkey")" \
              --epoch "$EPOCH" \
              --out-file pool-dereg.cert

            "''${CARDANO_CLI[@]}" transaction build-raw \
              --tx-in "$TXIN" \
              --certificate-file pool-dereg.cert \
              --fee "$FEE" \
              --tx-out "$CHANGE_ADDRESS+$CHANGE" \
              --out-file retire-bootstrap.txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file retire-bootstrap.txbody \
              --signing-key-file "$(decrypt_check "$BOOTSTRAP_POOL_COLD_KEY.skey")" \
              --signing-key-file "$(decrypt_check "$BOOTSTRAP_POOL_PAYMENT_KEY.skey")" \
              --signing-key-file "$(decrypt_check "$BOOTSTRAP_POOL_STAKING_KEY.skey")" \
              --out-file retire-bootstrap.txsigned

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file retire-bootstrap.txsigned
            fi
          '';
        };

        job-rotate-kes-pools = writeShellApplication {
          name = "job-rotate-kes-pools";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $CURRENT_KES_PERIOD
            #   [$DEBUG]
            #   [$ERA_CMD]
            #   [$NO_DEPLOY_DIR]
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

              # The cardano-cli cmd for node 8.7.2 will append to the skey if the file already exists
              rm "$DEPLOY_FILE"-kes.{skey,vkey}

              "''${CARDANO_CLI[@]}" node key-gen-KES \
                --signing-key-file "$DEPLOY_FILE"-kes.skey \
                --verification-key-file "$DEPLOY_FILE"-kes.vkey

              "''${CARDANO_CLI[@]}" node issue-op-cert \
                --kes-verification-key-file "$DEPLOY_FILE"-kes.vkey \
                --cold-signing-key-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.skey)" \
                --operational-certificate-issue-counter-file "$(decrypt_check "$NO_DEPLOY_FILE"-cold.counter)" \
                --kes-period "$CURRENT_KES_PERIOD" \
                --out-file "$DEPLOY_FILE".opcert

              chmod 0600 "$DEPLOY_FILE"{.opcert,-kes.skey,-kes.vkey}

              encrypt_check "$DEPLOY_FILE"-kes.skey
              encrypt_check "$DEPLOY_FILE"-kes.vkey
              encrypt_check "$DEPLOY_FILE".opcert

              # Generate bulk creds file for single pool use
              (for FILE in "$DEPLOY_FILE"{.opcert,-vrf.skey,-kes.skey}; do
                eval cat "$(decrypt_check "$FILE")"
              done) \
                | jq -s \
                | jq -s \
                > "$DEPLOY_FILE"-bulk.creds

              encrypt_check "$DEPLOY_FILE"-bulk.creds
            done

            # Generate bulk creds for all pools in the pool names
            (for ((i=0; i < ''${#POOLS[@]}; i++)); do
              (for FILE in "$STAKE_POOL_DIR/deploy/''${POOLS[$i]}"{.opcert,-vrf.skey,-kes.skey}; do
                eval cat "$(decrypt_check "$FILE")"
              done) | jq -s
            done) | jq -s > "$NO_DEPLOY_DIR/bulk.creds.pools.json"

            encrypt_check "$NO_DEPLOY_DIR/bulk.creds.pools.json"
          '';
        };

        job-move-genesis-utxo = writeShellApplication {
          name = "job-move-genesis-utxo";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $BYRON_SIGNING_KEY
            #   [$BYRON_UTXO]
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
            #   $PAYMENT_KEY
            #   [$SUBMIT_TX]
            #   $TESTNET_MAGIC
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            if [ -z "''${BYRON_UTXO:-}" ]; then
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
            fi

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

        job-update-proposal-generic = writeShellApplication {
          name = "job-update-proposal-generic";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
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

        job-update-proposal-d = writeShellApplication {
          name = "job-update-proposal-d";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   $D_VALUE
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
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

        job-update-proposal-hard-fork = writeShellApplication {
          name = "job-update-proposal-hard-fork";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
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

        job-update-proposal-cost-model = writeShellApplication {
          name = "job-update-proposal-cost-model";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $COST_MODEL
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
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

        job-update-proposal-mainnet-params = writeShellApplication {
          name = "job-update-proposal-mainnet-params";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$ERA] (deprecated `--$ERA-era` flag)
            #   [$ERA_CMD]
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

        job-submit-gov-action = writeShellApplication {
          name = "job-submit-gov-action";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $ACTION
            #   [$DEBUG]
            #   [$ERA_CMD]
            #   [$GOV_ACTION_DEPOSIT]
            #   $PAYMENT_KEY
            #   $PROPOSAL_ARGS
            #   [$PROPOSAL_HASH]
            #   [$PROPOSAL_URL]
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

            ACTION=''${ACTION:-"create-constitution"}
            GOV_ACTION_DEPOSIT=''${GOV_ACTION_DEPOSIT:-"0"}
            PROPOSAL_ARGS=("$@")
            PROPOSAL_HASH=''${PROPOSAL_HASH:-"0000000000000000000000000000000000000000000000000000000000000000"}
            PROPOSAL_URL=''${PROPOSAL_URL:-"https://proposals.sancho.network/1"}

            WITNESSES=2
            DEPOSIT_STAKE_KEY_ARGS=("--deposit-return-stake-verification-key-file" "$(decrypt_check "$STAKE_KEY".vkey)")

            CHANGE_ADDRESS=$(
              "''${CARDANO_CLI[@]}" address build \
                --payment-verification-key-file "$(decrypt_check "$PAYMENT_KEY".vkey)" \
                --testnet-magic "$TESTNET_MAGIC"
            )

            "''${CARDANO_CLI[@]}" governance action "$ACTION" \
              --testnet \
              "''${DEPOSIT_STAKE_KEY_ARGS[@]}" \
              --governance-action-deposit "$GOV_ACTION_DEPOSIT" \
              --anchor-url "$PROPOSAL_URL" \
              --anchor-data-hash "$PROPOSAL_HASH" \
              "''${PROPOSAL_ARGS[@]}" \
              --out-file "$ACTION".action


            # Generate transaction
            TXIN=$(
              "''${CARDANO_CLI[@]}" query utxo \
                --address "$CHANGE_ADDRESS" \
                --testnet-magic "$TESTNET_MAGIC" \
                --out-file /dev/stdout \
              | jq -r '(to_entries | sort_by(.value.value.lovelace) | reverse)[0].key'
            )

            # Generate arrays needed for build/sign commands
            BUILD_TX_ARGS+=("--proposal-file" "$ACTION".action)
            SIGN_TX_ARGS+=("--signing-key-file" "$(decrypt_check "$STAKE_KEY".skey)")

            "''${CARDANO_CLI[@]}" transaction build \
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

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-"$ACTION".txsigned
            fi
          '';
        };

        job-submit-vote = writeShellApplication {
          name = "job-submit-vote";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   $ACTION_TX_ID
            #   [$DEBUG]
            #   [$ERA_CMD]
            #   $DECISION
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
              VOTE_ARGS+=("--cc-hot-verification-key-file" "$(decrypt_check "$VOTE_KEY".vkey)")
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
            "''${CARDANO_CLI[@]}" governance vote create "''${VOTE_ARGS[@]}" --out-file "$ROLE".vote

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

            "''${CARDANO_CLI[@]}" transaction build \
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

        job-register-drep = writeShellApplication {
          name = "job-register-drep";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   [$DREP_DEPOSIT]
            #   $STAKE_DEPOSIT
            #   $DREP_DIR
            #   [$ERA_CMD]
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

            DREP_DEPOSIT=''${DREP_DEPOSIT:-"0"}
            mkdir -p "$DREP_DIR"

            "''${CARDANO_CLI[@]}" address key-gen \
              --verification-key-file "$DREP_DIR"/pay-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/pay-"$INDEX".skey

            "''${CARDANO_CLI[@]}" stake-address key-gen \
              --verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --signing-key-file "$DREP_DIR"/stake-"$INDEX".skey

            "''${CARDANO_CLI[@]}" governance drep key-gen \
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
              --key-reg-deposit-amt "$STAKE_DEPOSIT" \
              --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --out-file drep-"$INDEX"-stake.cert

            "''${CARDANO_CLI[@]}" governance drep registration-certificate \
              --drep-verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --key-reg-deposit-amt "$DREP_DEPOSIT" \
              --out-file drep-"$INDEX"-drep.cert

            "''${CARDANO_CLI[@]}" stake-address vote-delegation-certificate \
              --stake-verification-key-file "$DREP_DIR"/stake-"$INDEX".vkey \
              --drep-verification-key-file "$DREP_DIR"/drep-"$INDEX".vkey \
              --out-file drep-"$INDEX"-delegation.cert

            WITNESSES=3
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

            "''${CARDANO_CLI[@]}" transaction build \
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
              --signing-key-file "$DREP_DIR"/stake-"$INDEX".skey \
              --signing-key-file "$DREP_DIR"/drep-"$INDEX".skey

            fd --type file . "$DREP_DIR"/ --exec bash -c 'encrypt_check {}'

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-drep-"$INDEX".txsigned
            fi
          '';
        };

        job-register-cc = writeShellApplication {
          name = "job-register-cc";
          runtimeInputs = with pkgs; [coreutils jq];
          text = ''
            # Inputs:
            #   $CC_DIR
            #   [$DEBUG]
            #   [$ERA_CMD]
            #   $INDEX
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

            "''${CARDANO_CLI[@]}" governance committee create-hot-key-authorization-certificate \
              --cold-verification-key-file "$CC_DIR"/cold-"$INDEX".vkey \
              --hot-key-file "$CC_DIR"/hot-"$INDEX".vkey \
              --out-file cc-"$INDEX"-reg.cert

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

            "''${CARDANO_CLI[@]}" transaction build \
              --tx-in "$TXIN" \
              --change-address "$CHANGE_ADDRESS" \
              --witness-override "$WITNESSES" \
              --testnet-magic "$TESTNET_MAGIC" \
              --certificate cc-"$INDEX"-reg.cert \
              --out-file tx-cc-"$INDEX".txbody

            "''${CARDANO_CLI[@]}" transaction sign \
              --tx-body-file tx-cc-"$INDEX".txbody \
              --out-file tx-cc-"$INDEX".txsigned \
              --signing-key-file "$(decrypt_check "$PAYMENT_KEY".skey)" \
              --signing-key-file "$CC_DIR"/cold-"$INDEX".skey

            fd --type file . "$CC_DIR"/ --exec bash -c 'encrypt_check {}'

            if [ "''${SUBMIT_TX:-true}" = "true" ]; then
              "''${CARDANO_CLI[@]}" transaction submit --testnet-magic "$TESTNET_MAGIC" --tx-file tx-cc-"$INDEX".txsigned
            fi
          '';
        };

        job-gen-keys-cc = writeShellApplication {
          name = "job-register-cc";
          runtimeInputs = with pkgs; [coreutils jq];
          text = ''
            # Inputs:
            #   $CC_DIR
            #   [$DEBUG]
            #   $INDEX
            #   [$UNSTABLE]
            #   [$USE_DECRYPTION]
            #   [$USE_ENCRYPTION]
            #   [$USE_SHELL_BINS]

            [ -n "''${DEBUG:-}" ] && set -x

            ${secretsFns}
            ${selectCardanoCli}

            mkdir -p "$CC_DIR"

            "''${CARDANO_CLI[@]}" governance committee key-gen-cold \
              --verification-key-file "$CC_DIR"/cold-"$INDEX".vkey \
              --signing-key-file "$CC_DIR"/cold-"$INDEX".skey

            "''${CARDANO_CLI[@]}" governance committee key-gen-hot \
              --verification-key-file "$CC_DIR"/hot-"$INDEX".vkey \
              --signing-key-file "$CC_DIR"/hot-"$INDEX".skey
          '';
        };

        job-delegate-drep = writeShellApplication {
          name = "job-delegate-drep";
          runtimeInputs = stdPkgs;
          text = ''
            # Inputs:
            #   [$DEBUG]
            #   $DREP_KEY
            #   [$ERA_CMD]
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

            "''${CARDANO_CLI[@]}" stake-address vote-delegation-certificate \
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

            "''${CARDANO_CLI[@]}" transaction build \
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
