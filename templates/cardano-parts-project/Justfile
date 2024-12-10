import? 'scripts/recipes-aws.just'
import? 'scripts/recipes-custom.just'
import? 'scripts/recipes-governance.just'

set shell := ["bash", "-uc"]
set positional-arguments
alias terraform := tofu
alias tf := tofu

# Defaults
null := ""
stateDir := "STATEDIR=" + statePrefix / "$(basename $(git remote get-url origin))"
statePrefix := "~/.local/share"

# To skip ptrace permission modification prompting, env var AUTO_SET_ENV can be set to `false`
autoSetEnv := env_var_or_default("AUTO_SET_ENV","unset")

# Environment variables can be used to change the default template diff and path comparison sources.
# If TEMPLATE_PATH is set, it will have precedence, otherwise git url will be used for source templates.
templateBranch := env_var_or_default("TEMPLATE_BRANCH","main")
templatePath := env_var_or_default("TEMPLATE_PATH","no-path-given")
templateRepo := env_var_or_default("TEMPLATE_REPO","cardano-parts")
templateUrl := "https://raw.githubusercontent.com/input-output-hk/" + templateRepo + "/" + templateBranch + "/templates/cardano-parts-project"

# Common code
checkEnv := '''
  TESTNET_MAGIC="${2:-""}"
''' + checkEnvWithoutOverride + '''
  # Allow a magic override if the just recipe optional var is provided
  if ! [ -z "${TESTNET_MAGIC:-}" ]; then
    MAGIC="$TESTNET_MAGIC"
  fi
'''

checkEnvWithoutOverride := '''
  ENV="${1:-}"

  if ! [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^private$|^sanchonet$|^shelley-qa$|^demo$ ]]; then
    echo "Error: only node environments for demo, mainnet, preprod, preview, private, sanchonet and shelley-qa are supported"
    exit 1
  fi

  if [ "$ENV" = "mainnet" ]; then
    MAGIC="764824073"
  elif [ "$ENV" = "preprod" ]; then
    MAGIC="1"
  elif [ "$ENV" = "preview" ]; then
    MAGIC="2"
  elif [ "$ENV" = "shelley-qa" ]; then
    MAGIC="3"
  elif [ "$ENV" = "sanchonet" ]; then
    MAGIC="4"
  elif [ "$ENV" = "private" ]; then
    MAGIC="5"
  elif [ "$ENV" = "demo" ]; then
    MAGIC="42"
  fi
'''

checkSshConfig := '''
  if not ('.ssh_config' | path exists) {
    print $"(ansi "bg_light_red")Please run:(ansi reset) `just save-ssh-config` first to create the .ssh_config file"
    exit 1
  }

  let checkFile = '.consistency-check-ts'

  # Checking modified timestamps to decide whether to eval nixosCfgs which costs ~0.5s per ssh command
  let runCheck = if ($checkFile | path exists) {
    let checkTs = (stat -c %Y $checkFile) | into int
    let colmenaTs = (stat -c %Y flake/colmena.nix) | into int
    let sshHostsTs = (stat -c %Y .ssh_config) | into int
    let moduleIpsTs = if ('flake/nixosModules/ips-DONT-COMMIT.nix' | path exists) {
      (stat -c %Y flake/nixosModules/ips-DONT-COMMIT.nix) | into int
    } else {
      0
    }

    ($checkTs < $colmenaTs) or ($checkTs < $sshHostsTs) or ($checkTs < $moduleIpsTs)
  } else {
    true
  }

  # Sanity check nixosConfigurations, ssh hosts and module ips agree
  if ($runCheck == true) {
    print "Checking nixosCfg, sshCfg and ipModuleCfg for consistency"

    def list-diff [left: list<any>, right: list<any>, lName: string, rName: string]: nothing -> table<item: any, where: string> {
      let comparison = {
        $lName: ($left | where $it not-in $right)
        $rName: ($right | where $it not-in $left)
        =: ($left | where $it in $right)
      }

      $comparison | transpose where item | flatten | select item where | sort-by item
    }

    mut consistent = true

    let nixosCfg = (nix eval --json '.#nixosConfigurations' --apply 'builtins.attrNames') | from json

    # Ssh config header manual changes can be made without breaking parsing as
    # long as they come after the `Host *$` line. Host modifications can also be
    # made as long as any host changes come after the `  HostName .*$` line for
    # each respective host.
    let sshCfg = (open .ssh_config
      | parse --regex '(?m)Host (.*)\n\s+HostName (.*)'
      | rename machine ip
      | sort-by machine)

    let ssh4Cfg = ($sshCfg
      | where not ($it.machine | str ends-with ".ipv6")
      | rename machine pubIpv4
      | sort-by machine)

    let ssh6Cfg = ($sshCfg
      | where ($it.machine | str ends-with ".ipv6")
      | rename machine pubIpv6
      | update machine {$in | str replace '.ipv6' ''}
      | update pubIpv6 {if ($in == "unavailable.ipv6") { null } else { $in }}
      | sort-by machine)

    let moduleIps = if ('flake/nixosModules/ips-DONT-COMMIT.nix' | path exists) {
      (open flake/nixosModules/ips-DONT-COMMIT.nix
        | parse --regex '(?ms)(.*)^  };\nin {.*'
        | get capture0
        | parse --regex '(?m)    (.*) = {$\n\s+privateIpv4 = \"(.*)";\n\s+publicIpv4 = \"(.*)";\n\s+publicIpv6 = \"(.*)";\n\s+};'
        | rename machine privIpv4 pubIpv4 pubIpv6
        | update pubIpv6 {if ($in == "") { null } else { $in }}
        | sort-by machine)
    } else {
      []
    }

    # Set up comparison between list of nixos config machine names and ssh ipv4 machine names
    let nixCompareSsh4 = list-diff $nixosCfg ($ssh4Cfg | get machine) onlyInNixosCfg onlyInSshCfg | where where != "="

    # Set up comparison between list of ssh public ipv4 and ssh public ipv6 machine names
    let ssh4CompareSsh6 = list-diff ($ssh4Cfg | get machine) ($ssh6Cfg | get machine) onlyInSsh4Cfg onlyInSsh6Cfg | where where != "="

    # Set up comparison between list of nixos config machine names and ip module machine names
    let nixCompareIps = if ('flake/nixosModules/ips-DONT-COMMIT.nix' | path exists) {
      list-diff $nixosCfg ($moduleIps | get machine) onlyInNixosCfg onlyInIpsModuleCfg | where where != "="
    } else {
      []
    }

    # Set up comparison between list of ssh public ipv4 and ip module public ipv4 values
    let ssh4CompareIps4 = if ('flake/nixosModules/ips-DONT-COMMIT.nix' | path exists) {
      list-diff ($ssh4Cfg | get pubIpv4) ($moduleIps | get pubIpv4) onlyInSshCfg onlyInIpsModuleCfg | where where != "="
    } else {
      []
    }

    # Set up comparison between list of ssh public ipv6 and ip module public ipv6 values
    let ssh6CompareIps6 = if ('flake/nixosModules/ips-DONT-COMMIT.nix' | path exists) {
      list-diff ($ssh6Cfg | get pubIpv6) ($moduleIps | get pubIpv6) onlyInSshCfg onlyInIpsModuleCfg | where where != "="
    } else {
      []
    }

    # Validation output of any nixos config vs ssh ipv4 machine name differences
    if ($nixCompareSsh4 | is-not-empty) {
      print $"(ansi "bg_light_red")WARNING:(ansi reset) NixosConfigurations \(($nixosCfg | length)\) differ from ssh hosts \(($ssh4Cfg | length)\)"
      print "         You may need to run `just save-ssh-config` or `just tf apply` to update the .ssh_config file."
      print "         Differences found are:"
      print $nixCompareSsh4
      print ""
      $consistent = false
    }

    # Validation output of any nixos config vs ip module machine name differences
    if ($nixCompareIps | is-not-empty) {
      print $"(ansi "bg_light_red")WARNING:(ansi reset) NixosConfigurations \(($nixosCfg | length)\) differ from ip module machines \(($moduleIps | length)\)"
      print "         You may need to run `just update-ips` to update the flake/nixosModules/ips-DONT-COMMIT.nix file."
      print "         Differences found are:"
      print $nixCompareIps
      print ""
      $consistent = false
    }

    # Validation output of any ssh ipv4 vs ssh ipv6 machine name differences
    if ($ssh4CompareSsh6 | is-not-empty) {
      print $"(ansi "bg_light_red")WARNING:(ansi reset) Ssh config for public ipv4 \(($ssh4Cfg | length)\) differs from ssh config for public ipv6 hosts \(($ssh6Cfg | length)\)"
      print "         You may need to run `just save-ssh-config` or `just tf apply` to update the .ssh_config file."
      print "         Differences found are:"
      print $ssh4CompareSsh6
      print ""
      $consistent = false
    }

    # Validation output of any ssh public ipv4 vs ip module public ipv4 value differences
    if ($ssh4CompareIps4 | is-not-empty) {
      print $"(ansi "bg_light_red")WARNING:(ansi reset) Ssh config for public ipv4 differs from ip module public ipv4 config:"
      print "         You may need to run `just update-ips` to update the flake/nixosModules/ips-DONT-COMMIT.nix file."
      print "         Differences found are:"
      print $ssh4CompareIps4
      print ""
      $consistent = false
    }

    # Validation output of any ssh public ipv6 vs ip module public ipv6 value differences
    if ($ssh6CompareIps6 | is-not-empty) {
      print $"(ansi "bg_light_red")WARNING:(ansi reset) Ssh config for public ipv6 differs from ip module public ipv6 config:"
      print "         You may need to run `just update-ips` to update the flake/nixosModules/ips-DONT-COMMIT.nix file."
      print "         Differences found are:"
      print $ssh6CompareIps6
      print ""
      $consistent = false
    }

    if ($consistent == true) {
      touch $checkFile
    }
  }
'''

checkSshKey := '''
  if not ('.ssh_key' | path exists) {
    just save-bootstrap-ssh-key
  }
'''

sopsConfigSetup := '''
  # To support searching for sops config files from the target path rather than cwd up,
  # implement a userland solution until natively sops supported.
  #
  # This enables $NO_DEPLOY_DIR to be separate from the default $STAKE_POOL_DIR/no-deploy default location.
  # Ref: https://github.com/getsops/sops/issues/242#issuecomment-999809670
  function sops_config() {
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
    [ -n "${SHOPTS//[^x]/}" ] && set -x
  }
'''

# List all just recipes available
default:
  @just --list

# Deploy select machines
apply *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail

  CLICOLOR_FORCE=1 colmena apply --impure --verbose --color always --on {{ARGS}} \
    1> >(sed --regex '/.*colmena-assets-.*/ d; /.*• Added input .*/ {N;d}' >&1) \
    2> >(sed --regex '/.*colmena-assets-.*/ d; /• Added input .*/ {N;d}' >&2)

# Deploy all machines
apply-all *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail

  CLICOLOR_FORCE=1 colmena apply --impure --verbose --color always {{ARGS}} \
    1> >(sed --regex '/.*colmena-assets-.*/ d; /.*• Added input .*/ {N;d}' >&1) \
    2> >(sed --regex '/.*colmena-assets-.*/ d; /• Added input .*/ {N;d}' >&2)

# Deploy select machines with the bootstrap key
apply-bootstrap *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail

  sed '2i \ \ IdentityFile .ssh_key' .ssh_config > .ssh_config_bootstrap
  SSH_CONFIG_FILE=".ssh_config_bootstrap" just apply {{ARGS}}
  rm .ssh_config_bootstrap

# Build a nixos configuration
build-machine MACHINE *ARGS:
  nix build -L .#nixosConfigurations.{{MACHINE}}.config.system.build.toplevel {{ARGS}}

# Build all nixosConfigurations
build-machines *ARGS:
  #!/usr/bin/env nu
  let nodes = (nix eval --json '.#nixosConfigurations' --apply builtins.attrNames | from json)
  for node in $nodes {just build-machine $node {{ARGS}}}

# Run a local cardano-testnet
cardano-testnet isNg *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail

  if [ "{{isNg}}" = "true" ]; then
    CARDANO_CLI=$(command -v cardano-cli-ng)
    CARDANO_NODE=$(command -v cardano-node-ng)
    CARDANO_TESTNET="cardano-testnet-ng"
  elif [ "{{isNg}}" = "false" ]; then
    CARDANO_CLI=$(command -v cardano-cli)
    CARDANO_NODE=$(command -v cardano-node)
    CARDANO_TESTNET="cardano-testnet"
  else
    echo "ERROR: isNg must be either true to use the pre-release (aka next generation or \"ng\") version of node and cli,"
    echo "       or false to use the release version of node and cli."
    exit 1
  fi

  export CARDANO_CLI
  export CARDANO_NODE
  eval "$CARDANO_TESTNET" {{ARGS}}

# Deploy a cloudFormation stack
cf STACKNAME:
  #!/usr/bin/env nu
  mkdir cloudFormation
  nix eval --json '.#cloudFormation.{{STACKNAME}}' | from json | save --force 'cloudFormation/{{STACKNAME}}.json'
  rain deploy --debug --termination-protection --yes ./cloudFormation/{{STACKNAME}}.json

# Prep dbsync for delegation analysis
dbsync-prep ENV HOST ACCTS="501":
  #!/usr/bin/env bash
  set -euo pipefail
  TMPFILE="/tmp/create-faucet-stake-keys-table-{{ENV}}.sql"

  echo "Creating stake key sql injection command for environment {{ENV}} (this will take a minute)..."
  NOMENU=true \
  scripts/setup-delegation-accounts.py \
    --print-only \
    --wallet-mnemonic <(sops -d secrets/envs/{{ENV}}/utxo-keys/faucet.mnemonic) \
    --num-accounts {{ACCTS}} \
    > "$TMPFILE"

  echo
  echo "Pushing stake key sql injection command for environment {{ENV}}..."
  just scp "$TMPFILE" {{HOST}}:"$TMPFILE"

  echo
  echo "Executing stake key sql injection command for environment {{ENV}}..."
  just ssh {{HOST}} -t "psql -XU cexplorer cexplorer < \"$TMPFILE\""

# Start a remote dbsync psql session
dbsync-psql HOSTNAME:
  #!/usr/bin/env bash
  just ssh {{HOSTNAME}} -t 'psql -U cexplorer cexplorer'

# Analyze pool performance
dbsync-pool-analyze HOSTNAME TABLE="summary" PSQL_ARGS="-xX" LOVELACE="2E12":
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Pushing pool analysis sql command on {{HOSTNAME}}..."
  just scp scripts/dbsync-pool-perf.sql {{HOSTNAME}}:/tmp/

  echo
  echo "Executing pool analysis sql command on host {{HOSTNAME}} with:"
  echo "  Table: {{TABLE}}"
  echo "  Psql args: \"{{PSQL_ARGS}}\""
  echo "  Lovelace threshold (lt): {{LOVELACE}}"

  QUERY=$(just ssh {{HOSTNAME}} -t "'psql -P pager=off -v table={{TABLE}} -v lovelace={{LOVELACE}} -U cexplorer cexplorer {{PSQL_ARGS}} < /tmp/dbsync-pool-perf.sql'")
  if [ "{{TABLE}}" = "summary" ] && [ "{{PSQL_ARGS}}" = "-xX" ]; then
    echo
    echo "Query output:"
    echo "$QUERY" | tail -n +2
    echo

    JSON=$(grep -oP '^faucet_pool_summary_json[[:space:]]+\| \K{.*$' <<< "$QUERY" | jq .)
    DEDELEGATE_POOLS=$(jq '.faucet_to_dedelegate' <<< "$JSON")
    echo "$JSON"
    echo

    echo "Faucet pools to de-delegate are:"
    echo "$DEDELEGATE_POOLS"
    echo

    if [ "$DEDELEGATE_POOLS" != "null" ]; then
      echo "The string of indexes of faucet pools to de-delegate from the JSON above are:"
      jq -r '.faucet_to_dedelegate | to_entries | map(.key) | join(" ")' <<< "$JSON"
      echo

      MAX_SHIFT=$(grep -oP '^faucet_pool_to_dedelegate_shift_pct[[:space:]]+\| \K.*$' <<< "$QUERY")
      echo "The maximum percentage difference de-delegation of all these pools will make in chain density is: $MAX_SHIFT"
    else
      echo "There are no faucet delegated non-performing pools to de-delegate at this time."
    fi
  else
    echo "$QUERY"
  fi

# De-delegation pools for given faucet stake indexes
dedelegate-pools ENV *IDXS=null:
  #!/usr/bin/env bash
  set -euo pipefail
  {{checkEnvWithoutOverride}}

  if ! [[ "$ENV" =~ ^preprod$|^preview$|^private$|^sanchonet$|^shelley-qa$ ]]; then
    echo "Error: only node environments for preprod, preview, private, sanchonet and shelley-qa are supported"
    exit 1
  fi

  if [ "{{ENV}}" = "mainnet" ]; then
    echo "Dedelegation cannot be performed on the mainnet environment"
    exit 1
  fi
  just set-default-cardano-env {{ENV}} "$MAGIC" "$PPID"

  if [ "$(jq -re .syncProgress <<< "$(just query-tip {{ENV}})")" != "100.00" ]; then
    echo "Please wait until the local tip of environment {{ENV}} is 100.00 before dedelegation"
    exit 1
  fi

  if [ "${USE_SHELL_BINS:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ -n "${UNSTABLE:-}" ] && [ "${UNSTABLE:-}" != "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ "${UNSTABLE:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli-ng"
  elif [[ "$ENV" =~ ^preprod$|^preview$|^shelley-qa$ ]]; then
    CARDANO_CLI="cardano-cli"
  elif [[ "$ENV" =~ ^private$|^sanchonet$ ]]; then
    CARDANO_CLI="cardano-cli-ng"
  fi

  echo
  read -p "Press any key to start de-delegating {{ENV}} faucet pool delegations for stake key indexes {{IDXS}}" -n 1 -r -s
  echo
  echo "Starting de-delegation of the following stake key indexes: {{IDXS}}"
  for i in {{IDXS}}; do
    echo "De-delegating index $i"
    NOMENU=true scripts/restore-delegation-accounts.py \
      --testnet-magic "$MAGIC" \
      --signing-key-file <(just sops-decrypt-binary secrets/envs/{{ENV}}/utxo-keys/rich-utxo.skey) \
      --wallet-mnemonic <(just sops-decrypt-binary secrets/envs/{{ENV}}/utxo-keys/faucet.mnemonic) \
      --delegation-index "$i"

    TXID=$(eval "$CARDANO_CLI" latest transaction txid --tx-file tx-deleg-account-$i-restore.txsigned)
    EXISTS="true"

    while [ "$EXISTS" = "true" ]; do
      EXISTS=$(eval "$CARDANO_CLI" latest query tx-mempool tx-exists $TXID | jq -r .exists)
      if [ "$EXISTS" = "true" ]; then
        echo "Pool de-delegation index $i tx still exists in the mempool, sleeping 5s: $TXID"
      else
        echo "Pool de-delegation index $i tx has been removed from the mempool."
      fi
      sleep 5
    done
    echo
    echo
  done

# Get a wallet address from mnemonic file
gen-payment-address FILE OFFSET="0":
  cardano-address key from-recovery-phrase Shelley < {{FILE}} \
    | cardano-address key child 1852H/1815H/0H/0/{{OFFSET}} \
    | cardano-address key public --with-chain-code \
    | cardano-address address payment --network-tag testnet

# Standard lint check
lint:
  deadnix -f
  statix check

# List machines
list-machines:
  #!/usr/bin/env nu
  let nixosNodes = (do -i { ^nix eval --json '.#nixosConfigurations' --apply 'builtins.attrNames' } | complete)
  if $nixosNodes.exit_code != 0 {
     print "Nixos failed to evaluate the .#nixosConfigurations attribute."
     print "The output was:"
     print
     print $nixosNodes
     exit 1
  }

  {{checkSshConfig}}

  let sshNodes = (do -i { ^scj dump /dev/stdout -c .ssh_config } | complete)
  if $sshNodes.exit_code != 0 {
     print "Ssh-config-json failed to evaluate the .ssh_config file."
     print "The output was:"
     print
     print $sshNodes
     exit 1
  }

  let nixosNodesDfr = (
    let nodeList = ($nixosNodes.stdout | from json);
    let sanitizedList = (if ($nodeList | is-empty) {$nodeList | insert 0 ""} else {$nodeList});

    $sanitizedList
      | insert 0 "machine"
      | each {|i| [$i] | into record}
      | headers
      | each {|i| insert inNixosCfg {"yes"}}
      | dfr into-df
  )

  let sshNodesDfr = (
    let ssh4Table = ($sshNodes.stdout
      | from json
      | where ('HostName' in $it) and not ($it.Host | str ends-with ".ipv6")
      | select Host HostName
      | rename Host pubIpv4
    );

    let ssh6Table = ($sshNodes.stdout
      | from json
      | where ('HostName' in $it) and ($it.Host | str ends-with ".ipv6")
      | select Host HostName
      | rename Host pubIpv6
      | update Host {$in | str replace '.ipv6' ''}
      | update pubIpv6 {if ($in == "unavailable.ipv6") { null } else { $in }}
      | select Host pubIpv6
    );

    let sshTable = ($ssh4Table
      | dfr into-df
      | dfr join -o ($ssh6Table | dfr into-df) Host Host
    );

    if ($sshTable | is-empty) {
      [[Host pubIpv4 pubIpv6]; ["" "" ""]] | dfr into-df
    }
    else {
      $sshTable
    }
  )

  (
    $nixosNodesDfr
      | dfr join -o $sshNodesDfr machine Host
      | dfr sort-by machine
      | dfr into-nu
      | update inNixosCfg {if $in == null {$"(ansi bg_red)Missing(ansi reset)"} else {$in}}
      | update pubIpv4 {if $in == null {$"(ansi bg_red)Missing(ansi reset)"} else {$in}}
      | update pubIpv6 {|row|
        if (
          (($row.inNixosCfg | str contains "Missing") or ($row.pubIpv4 | str contains "Missing"))
            and
          ($row.pubIpv6 == null)
        ) {$"(ansi bg_red)Missing(ansi reset)"} else {$in} }
      | where machine != ""
  )

# Check mimir required config
mimir-alertmanager-bootstrap:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Enter the mimir admin username: "
  read -s MIMIR_USER
  echo

  echo "Enter the mimir admin token: "
  read -s MIMIR_TOKEN
  echo

  echo "Enter the mimir base monitoring fqdn without the HTTPS:// scheme: "
  read URL
  echo

  echo "Obtaining current mimir alertmanager config:"
  echo "-----------"
  mimirtool alertmanager get --address "https://$MIMIR_USER:$MIMIR_TOKEN@$URL/mimir" --id 1
  echo "-----------"

  echo
  echo "If the output between the dashed lines above is blank, you may need to preload an initial alertmanager ruleset"
  echo "for the mimir TF plugin to succeed, where the command to preload alertmanager is:"
  echo
  echo "mimirtool alertmanager load --address \"https://\$MIMIR_USER:\$MIMIR_TOKEN@$URL/mimir\" --id 1 alertmanager-bootstrap-config.yaml"
  echo
  echo "The contents of alertmanager-bootstrap-config.yaml can be:"
  echo
  echo "route:"
  echo "  group_wait: 0s"
  echo "  receiver: empty-receiver"
  echo "receivers:"
  echo "  - name: 'empty-receiver'"

# Query the tip of all running envs
query-tip-all:
  #!/usr/bin/env bash
  set -euo pipefail
  QUERIED=0
  for i in mainnet preprod preview private shelley-qa sanchonet demo; do
    TIP=$(just query-tip $i 2>&1) && {
      echo "Environment: $i"
      echo "$TIP"
      echo
      QUERIED=$((QUERIED + 1))
    }
  done
  [ "$QUERIED" = "0" ] && echo "No environments running." || true

# Query the current envs tip
query-tip ENV TESTNET_MAGIC=null:
  #!/usr/bin/env bash
  set -euo pipefail
  {{checkEnv}}
  {{stateDir}}

  if [ "${USE_SHELL_BINS:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ -n "${UNSTABLE:-}" ] && [ "${UNSTABLE:-}" != "true" ]; then
    CARDANO_CLI="cardano-cli"
  elif [ "${UNSTABLE:-}" = "true" ]; then
    CARDANO_CLI="cardano-cli-ng"
  elif [[ "$ENV" =~ ^mainnet$|^preprod$|^preview$|^shelley-qa$ ]]; then
    CARDANO_CLI="cardano-cli"
  elif [[ "$ENV" =~ ^private$|^sanchonet$|^demo$ ]]; then
    CARDANO_CLI="cardano-cli-ng"
  fi

  eval "$CARDANO_CLI" latest query tip \
    --socket-path "$STATEDIR/node-{{ENV}}.socket" \
    --testnet-magic "$MAGIC"

# Save the cluster bootstrap ssh key
save-bootstrap-ssh-key:
  #!/usr/bin/env nu
  print "Retrieving ssh key from tofu..."
  nix build ".#opentofu.cluster" --out-link terraform.tf.json
  tofu init -reconfigure
  tofu workspace select -or-create cluster
  let tf = (tofu show -json | from json)
  let key = ($tf.values.root_module.resources | where type == tls_private_key and name == bootstrap)
  $key.values.private_key_openssh | to text | save --force .ssh_key
  chmod 0600 .ssh_key

# Save bulk credentials from select commit
save-bulk-creds ENV COMMIT="HEAD":
  #!/usr/bin/env bash
  mkdir -p workbench/custom/rundir
  DATE=$(git show --no-patch --format=%cs {{COMMIT}})
  for i in 1 2 3; do
    sops --config /dev/null --input-type binary --output-type binary --decrypt \
    <(git cat-file blob {{COMMIT}}:secrets/groups/{{ENV}}$i/no-deploy/bulk.creds.pools.json) \
    | jq -r '.[]'
  done \
    | jq -s \
      > "workbench/custom/rundir/bulk.creds.secret.{{ENV}}.{{COMMIT}}.$DATE.pools.json"

  echo
  echo "Bulk credentials file for environment {{ENV}}, commit {{COMMIT}} has been saved at:"
  echo "  workbench/custom/rundir/bulk.creds.secret.{{ENV}}.{{COMMIT}}.$DATE.pools.json"
  echo
  echo "Do not commit this file and delete it when local workbench work is completed."

# Save ssh config
save-ssh-config:
  #!/usr/bin/env nu
  print "Retrieving ssh config from tofu..."
  nix build ".#opentofu.cluster" --out-link terraform.tf.json
  tofu init -reconfigure
  tofu workspace select -or-create cluster
  let tf = (tofu show -json | from json)
  let key = ($tf.values.root_module.resources | where type == local_file and name == ssh_config)
  $key.values.content | to text | save --force .ssh_config
  chmod 0600 .ssh_config

# Set the shell's default node env
set-default-cardano-env ENV TESTNET_MAGIC=null PPID=null:
  #!/usr/bin/env bash
  set -euo pipefail
  {{checkEnv}}
  {{stateDir}}
  # The log and socket file may not exist immediately upon node startup, so only check for the pid file
  if ! [ -s "$STATEDIR/node-{{ENV}}.pid" ]; then
    echo "Environment {{ENV}} does not appear to be running as $STATEDIR/node-{{ENV}}.pid does not exist"
    exit 1
  fi

  echo "Linking: $(ln -sfv "$STATEDIR/node-{{ENV}}.socket" node.socket)"
  echo "Linking: $(ln -sfv "$STATEDIR/node-{{ENV}}.log" node.log)"
  echo

  if [ -n "{{PPID}}" ]; then
    PARENTID="{{PPID}}"
  else
    PARENTID="$PPID"
  fi

  SHELLPID=$(cat /proc/$PARENTID/status | awk '/PPid/ {print $2}')
  DEFAULT_PATH=$(pwd)/node.socket

  echo "Updating shell env vars:"
  echo "  CARDANO_NODE_SOCKET_PATH=$DEFAULT_PATH"
  echo "  CARDANO_NODE_NETWORK_ID=$MAGIC"
  echo "  TESTNET_MAGIC=$MAGIC"

  # Ptrace permissions are no longer "classic" by default starting in nixpkgs 24.05
  AUTO_SET_ENV={{autoSetEnv}}
  if [ -f /proc/sys/kernel/yama/ptrace_scope ] && [ "$AUTO_SET_ENV" != "false" ]; then
     if [ "$(cat /proc/sys/kernel/yama/ptrace_scope)" = "0" ]; then
       AUTO_SET_ENV=true
     else
       echo
       echo "For just scripts to automatically set cardano environment variables in bash and zsh shells, ptrace classic permission needs to be enabled."
       echo "This requires sudo access and will persist ptrace classic permission until the next reboot by writing:"
       echo "  echo 0 > /proc/sys/kernel/yama/ptrace_scope"
       echo
       read -p "Do you have sudo access and wish to proceed [yY]? " -n 1 -r
       echo
       if [[ $REPLY =~ ^[Yy]$ ]]; then
         if sudo bash -c 'echo 0 > /proc/sys/kernel/yama/ptrace_scope'; then
           echo "ptrace_scope classic permission successfully set."
           AUTO_SET_ENV=true
         else
           echo "ptrace_scope classic permission change unsuccessful."
         fi
       fi
     fi
  fi

  SH=$(cat /proc/$SHELLPID/comm)
  if [[ "$SH" =~ bash$|zsh$ ]] && [ "$AUTO_SET_ENV" = "true" ]; then
    # Modifying a parent shells env vars is generally not done
    # This is a hacky way to accomplish it in bash and zsh
    gdb -iex "set auto-load no" /proc/$SHELLPID/exe $SHELLPID <<END >/dev/null
      call (int) setenv("CARDANO_NODE_SOCKET_PATH", "$DEFAULT_PATH", 1)
      call (int) setenv("CARDANO_NODE_NETWORK_ID", "$MAGIC", 1)
      call (int) setenv("TESTNET_MAGIC", "$MAGIC", 1)
  END

    # Zsh env vars get updated, but the shell doesn't reflect this
    if [ "$SH" = "zsh" ]; then
      echo
      echo "Cardano env vars have been updated as seen by \`env\`, but zsh \`echo \$VAR\` will not reflect this."
      echo "To sync zsh shell vars with env vars:"
      echo "  source scripts/sync-env-vars.sh"
    fi
  else
    echo
    if ! [[ "$SH" =~ bash$|zsh$ ]]; then
      echo "Unexpected shell: $SH"
    fi

    if [ "$AUTO_SET_ENV" != "true" ]; then
      echo "ptrace_scope: classic permission not enabled"
    fi
    echo "The following vars will need to be manually exported, or the equivalent operation for your shell:"
    echo "  export CARDANO_NODE_SOCKET_PATH=$DEFAULT_PATH"
    echo "  export CARDANO_NODE_NETWORK_ID=$MAGIC"
    echo "  export TESTNET_MAGIC=$MAGIC"
  fi

# Show nix flake details
show-flake *ARGS:
  nix flake show --allow-import-from-derivation {{ARGS}}

# Show DNS nameservers
show-nameservers:
  #!/usr/bin/env nu
  let domain = (nix eval --raw '.#cardano-parts.cluster.infra.aws.domain')
  let zones = (aws route53 list-hosted-zones-by-name | from json).HostedZones
  let id = ($zones | where Name == $"($domain).").Id.0
  let sets = (aws route53 list-resource-record-sets --hosted-zone-id $id | from json).ResourceRecordSets
  let ns = ($sets | where Type == "NS").ResourceRecords.0.Value
  print "Nameservers for the following hosted zone need to be added to the NS record of the delegating authority"
  print $"Nameservers for domain: ($domain) \(hosted zone id: ($id)) are:"
  print ($ns | to text)

# Decrypt a file to stdout
sops-decrypt-binary FILE:
  #!/usr/bin/env bash
  set -euo pipefail
  {{sopsConfigSetup}}
  [ -n "${DEBUG:-}" ] && set -x

  # Default to stdout decrypted output.
  # This supports the common use case of obtaining decrypted state for cmd arg input while leaving the encrypted file intact on disk.
  sops --config "$(sops_config {{FILE}})" --input-type binary --output-type binary --decrypt {{FILE}}

# Decrypt a file in place
sops-decrypt-binary-in-place FILE:
  #!/usr/bin/env bash
  set -euo pipefail
  {{sopsConfigSetup}}
  [ -n "${DEBUG:-}" ] && set -x

  sops --config "$(sops_config {{FILE}})" --input-type binary --output-type binary --decrypt {{FILE}} | sponge {{FILE}}

# Encrypt a file in place
sops-encrypt-binary FILE:
  #!/usr/bin/env bash
  set -euo pipefail
  {{sopsConfigSetup}}
  [ -n "${DEBUG:-}" ] && set -x

  # Default to in-place encrypted output.
  # This supports the common use case of first time encrypting plaintext state for public storage, ex: git repo commit.
  sops --config "$(sops_config {{FILE}})" --input-type binary --output-type binary --encrypt {{FILE}} | sponge {{FILE}}

# Rotate sops encryption
sops-rotate-binary FILE:
  #!/usr/bin/env bash
  set -euo pipefail
  {{sopsConfigSetup}}
  [ -n "${DEBUG:-}" ] && set -x

  # Default to in-place encryption rotation.
  # This supports the common use case of rekeying, for example if recipient keys have changed.
  just sops-decrypt-binary {{FILE}} | sponge {{FILE}}
  just sops-encrypt-binary {{FILE}}

# Scp using repo ssh config
scp *ARGS:
  #!/usr/bin/env nu
  {{checkSshConfig}}
  scp -o LogLevel=ERROR -F .ssh_config {{ARGS}}

# Ssh using repo ssh config
ssh HOSTNAME *ARGS:
  #!/usr/bin/env nu
  {{checkSshConfig}}
  ssh -o LogLevel=ERROR -F .ssh_config {{HOSTNAME}} {{ARGS}}

# Generate example .ssh_config code
ssh-config-example:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "The following config example shows the expected struct of the \".ssh_config\" file."
  echo "This may be used as a template if a custom .ssh_config file needs to be"
  echo "created and managed manually, for example, in a non-aws environment."
  echo
  echo "Note that per host customization should come after the HostName line to preserve pattern parsing!"
  echo
  echo "---"
  echo
  cat <<"EOF"
  Host *
    User root
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    ServerAliveCountMax 2
    ServerAliveInterval 60

  Host machine-example-1
    HostName 1.2.3.4
    # Per host customization should come after the HostName line to preserve pattern parsing
    ProxyJump machine-example-2

  Host machine-example-1.ipv6
    HostName ff00::01

  Host machine-example-2
    HostName 1.2.3.5

  Host machine-example-2.ipv6
    HostName unavailable.ipv6
  EOF

# Ssh using cluster bootstrap key
ssh-bootstrap HOSTNAME *ARGS:
  #!/usr/bin/env nu
  {{checkSshConfig}}
  {{checkSshKey}}
  ssh -o LogLevel=ERROR -F .ssh_config -i .ssh_key {{HOSTNAME}} {{ARGS}}

# Ssh to all
ssh-for-all *ARGS:
  #!/usr/bin/env nu
  let nodes = (nix eval --json '.#nixosConfigurations' --apply builtins.attrNames | from json)
  $nodes | par-each {|node| just ssh -q $node {{ARGS}}}

# Ssh for select
ssh-for-each HOSTNAMES *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail

  CLICOLOR_FORCE=1 colmena exec --impure --verbose --parallel 0 --on {{HOSTNAMES}} {{ARGS}} \
    1> >(sed --regex '/.*colmena-assets-.*/ d; /.*• Added input .*/ {N;d}' >&1) \
    2> >(sed --regex '/.*colmena-assets-.*/ d; /• Added input .*/ {N;d}' >&2)

# List machine ips based on regex pattern
ssh-list-ips PATTERN:
  #!/usr/bin/env nu
  scj dump /dev/stdout -c .ssh_config
    | from json
    | default "" Host
    | default "" HostName
    | where not ($it.Host | str ends-with ".ipv6")
    | where Host =~ "{{PATTERN}}"
    | get HostName
    | str join " "

# List machine names based on regex pattern
ssh-list-names PATTERN:
  #!/usr/bin/env nu
  scj dump /dev/stdout -c .ssh_config
    | from json
    | default "" Host
    | default "" HostName
    | where not ($it.Host | str ends-with ".ipv6")
    | where Host =~ "{{PATTERN}}"
    | get Host
    | str join " "

# Start a fork to conway demo
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
  export KEY_DIR=state-demo/envs/custom
  export DATA_DIR=state-demo/rundir

  export CARDANO_NODE_SOCKET_PATH="$STATEDIR/node-demo.socket"
  export TESTNET_MAGIC=42

  export NUM_GENESIS_KEYS=3
  export POOL_NAMES="sp-1 sp-2 sp-3"
  export STAKE_POOL_DIR=state-demo/groups/stake-pools

  export BULK_CREDS=state-demo/bulk.creds.all.json
  export PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo

  export UNSTABLE=true
  export UNSTABLE_LIB=true
  export USE_ENCRYPTION=true
  export USE_DECRYPTION=true
  export USE_NODE_CONFIG_BP=false
  export USE_CREATE_TESTNET_DATA=false
  export DEBUG=true

  export SECURITY_PARAM=8
  export SLOT_LENGTH=100
  export START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds")
  if [ "$USE_CREATE_TESTNET_DATA" = true ]; then
    ERA_CMD="alonzo" \
      nix run .#job-gen-custom-node-config-data
  else
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
  just set-default-cardano-env demo "" "$PPID"
  echo "Sleeping 30 seconds until $(date -d  @$(($(date +%s) + 30)))"
  sleep 30
  echo

  if [ "$USE_CREATE_TESTNET_DATA" = false ]; then
    echo "Moving genesis utxo..."
    BYRON_SIGNING_KEY="$KEY_DIR"/utxo-keys/shelley.000.skey \
      ERA_CMD="alonzo" \
      nix run .#job-move-genesis-utxo
    echo "Sleeping 7 seconds until $(date -d  @$(($(date +%s) + 7)))"
    sleep 7
    echo
  fi

  echo "Registering stake pools..."
  POOL_RELAY=demo.local \
    POOL_RELAY_PORT=3001 \
    ERA_CMD="alonzo" \
    nix run .#job-register-stake-pools
  echo "Sleeping 7 seconds until $(date -d  @$(($(date +%s) + 7)))"
  sleep 7
  echo

  echo "Delegating rewards stake key..."
  ERA_CMD="alonzo" \
    nix run .#job-delegate-rewards-stake-key
  echo "Sleeping 160 seconds until $(date -d  @$(($(date +%s) + 160)))"
  sleep 160
  echo

  echo "Forking to babbage..."
  just query-tip demo
  MAJOR_VERSION=7 \
    ERA_CMD="alonzo" \
    nix run .#job-update-proposal-hard-fork
  echo "Sleeping 160 seconds until $(date -d  @$(($(date +%s) + 160)))"
  sleep 160
  echo

  echo "Forking to babbage (intra-era)..."
  just query-tip demo
  MAJOR_VERSION=8 \
    ERA_CMD="babbage" \
    nix run .#job-update-proposal-hard-fork
  echo "Sleeping 160 seconds until $(date -d  @$(($(date +%s) + 160)))"
  sleep 160
  echo

  echo "Forking to conway..."
  just query-tip demo
  MAJOR_VERSION=9 \
    ERA_CMD="babbage" \
    nix run .#job-update-proposal-hard-fork
  echo "Sleeping 160 seconds until $(date -d  @$(($(date +%s) + 160)))"
  sleep 160
  echo

  just query-tip demo
  echo
  echo "Finished sequence..."
  echo

# Start a local node for a specific env
start-node ENV:
  #!/usr/bin/env bash
  set -euo pipefail
  {{stateDir}}

  if ! [[ "{{ENV}}" =~ ^mainnet$|^preprod$|^preview$|^private$|^sanchonet$|^shelley-qa$ ]]; then
    echo "Error: only node environments for mainnet, preprod, preview, private, sanchonet and shelley-qa are supported for start-node recipe"
    exit 1
  fi

  # Stop any existing running local node env for a clean restart
  just stop-node {{ENV}}
  echo "Starting cardano-node for envrionment {{ENV}}"
  mkdir -p "$STATEDIR"

  if [[ "{{ENV}}" =~ ^mainnet$|^preprod$|^preview$ ]]; then
    UNSTABLE=false
    UNSTABLE_LIB=false
    UNSTABLE_MITHRIL=false
    USE_NODE_CONFIG_BP=false
  else
    UNSTABLE=true
    UNSTABLE_LIB=true
    UNSTABLE_MITHRIL=true
    USE_NODE_CONFIG_BP=false
  fi

  # Set required entrypoint vars and run node in a new nohup background session
  ENVIRONMENT="{{ENV}}" \
  UNSTABLE="$UNSTABLE" \
  UNSTABLE_LIB="$UNSTABLE_LIB" \
  UNSTABLE_MITHRIL="$UNSTABLE_MITHRIL" \
  USE_NODE_CONFIG_BP="$USE_NODE_CONFIG_BP" \
  DATA_DIR="$STATEDIR" \
  SOCKET_PATH="$STATEDIR/node-{{ENV}}.socket" \
  nohup setsid nix run .#run-cardano-node &> "$STATEDIR/node-{{ENV}}.log" & echo $! > "$STATEDIR/node-{{ENV}}.pid" &
  just set-default-cardano-env {{ENV}} "" "$PPID"

# Stop all local nodes
stop-all:
  #!/usr/bin/env bash
  set -euo pipefail
  for i in mainnet preprod preview private shelley-qa sanchonet demo; do
    just stop-node $i
  done

# Stop a local node for a specific env
stop-node ENV:
  #!/usr/bin/env bash
  set -euo pipefail
  {{stateDir}}

  if [ -f "$STATEDIR/node-{{ENV}}.pid" ]; then
    echo "Stopping cardano-node for envrionment {{ENV}}"
    kill $(< "$STATEDIR/node-{{ENV}}.pid") 2> /dev/null || true
    rm -f "$STATEDIR/node-{{ENV}}.pid" "$STATEDIR/node-{{ENV}}.socket"
  fi

# Clone a cardano-parts template
template-clone FILE:
  #!/usr/bin/env bash
  set -euo pipefail

  # If a local copy already exists and there is a diff, force awareness
  if [ -f "{{FILE}}" ]; then
    if ! git diff-index --quiet HEAD -- "{{FILE}}"; then
      echo "A local copy exists with uncommitted git modifications: {{FILE}}"
      echo "Please commit or revert modifications and try again."
      exit 1
    fi
  else
    # Ensure the path to it exists
    mkdir -p "$(dirname "{{FILE}}")"
  fi

  TMPFILE=$(mktemp -t template-clone-XXXXXX)
  if [ "{{templatePath}}" = "no-path-given" ]; then
    echo "Retreiving a template file copy from:"
    echo "  {{templateUrl}}/{{FILE}}"
    if ! curl -H 'Cache-Control: no-cache' -sL "{{templateUrl}}/{{FILE}}" > "$TMPFILE"; then
      echo "Unable to curl the requested resource successfully with:"
      echo "curl -H 'Cache-Control: no-cache' -sL \"{{templateUrl}}/{{FILE}}\" > \"$TMPFILE\""
      rm -f "$TMPFILE"
      exit 1
    fi
  else
    echo "Retreiving a template file copy from:"
    echo "  {{templatePath}}/{{FILE}}"
    if [ -f "{{templatePath}}/{{FILE}}" ]; then
      cp "{{templatePath}}/{{FILE}}" "$TMPFILE"
    else
      echo "Unable to find the requested template file at {{templatePath}}/{{FILE}}"
      exit 1
    fi
  fi

  echo
  echo "Moving the template file copy into place and setting file permissions to 0644"
  mv -f "$TMPFILE" "{{FILE}}"
  chmod 0644 "{{FILE}}"

  echo
  echo "Git adding file:"
  echo "  {{FILE}}"
  git add {{FILE}}

# Diff against cardano-parts template
template-diff FILE *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail
  if ! [ -f "{{FILE}}" ]; then
    FILE="<(echo '')"
  else
    FILE="{{FILE}}"
  fi

  if [ "{{templatePath}}" = "no-path-given" ]; then
    SRC_FILE="<(curl -H 'Cache-Control: no-cache' -sL \"{{templateUrl}}/{{FILE}}\")"
    SRC_NAME="{{templateUrl}}/{{FILE}}"
  else
    SRC_FILE="{{templatePath}}/{{FILE}}"
    SRC_NAME="$SRC_FILE"
  fi

  eval "icdiff -L {{FILE}} -L \"$SRC_NAME\" {{ARGS}} $FILE $SRC_FILE"

# Patch against cardano-parts template
template-patch FILE:
  #!/usr/bin/env bash
  set -euo pipefail
  if git status --porcelain "{{FILE}}" | grep -q "{{FILE}}"; then
    echo "Git file {{FILE}} is dirty.  Please revert or commit changes to clean state and try again."
    exit 1
  fi

  if [ "{{templatePath}}" = "no-path-given" ]; then
    SRC_FILE="<(curl -H 'Cache-Control: no-cache' -sL \"{{templateUrl}}/{{FILE}}\")"
  else
    SRC_FILE="{{templatePath}}/{{FILE}}"
  fi

  PATCH_FILE=$(eval "diff -Naru \"{{FILE}}\" $SRC_FILE || true")
  patch "{{FILE}}" < <(echo "$PATCH_FILE")
  git add -p "{{FILE}}"

# Run tofu for cluster or grafana workspace
tofu *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail
  IGREEN='\033[1;92m'
  IRED='\033[1;91m'
  NC='\033[0m'
  SOPS=("sops" "--input-type" "binary" "--output-type" "binary" "--decrypt")

  read -r -a ARGS <<< "{{ARGS}}"
  if [[ ${ARGS[0]} =~ cluster|grafana ]]; then
    WORKSPACE="${ARGS[0]}"
    ARGS=("${ARGS[@]:1}")
  else
    WORKSPACE="cluster"
  fi

  unset VAR_FILE
  if [ -s "secrets/tf/$WORKSPACE.tfvars" ]; then
    VAR_FILE="secrets/tf/$WORKSPACE.tfvars"
  fi

  echo -e "Running tofu in the ${IGREEN}$WORKSPACE${NC} workspace..."
  rm --force terraform.tf.json
  nix build ".#opentofu.$WORKSPACE" --out-link terraform.tf.json

  tofu init -reconfigure
  tofu workspace select -or-create "$WORKSPACE"
  tofu ${ARGS[@]} ${VAR_FILE:+-var-file=<("${SOPS[@]}" "$VAR_FILE")}

# Truncate a select chain after slot
truncate-chain ENV SLOT:
  #!/usr/bin/env bash
  set -euo pipefail
  [ -n "${DEBUG:-}" ] && set -x
  {{stateDir}}

  if ! [[ "{{ENV}}" =~ ^mainnet$|^preprod$|^preview$|^private$|^sanchonet$|^shelley-qa$ ]]; then
    echo "Error: only node environments for mainnet, preprod, preview, private, sanchonet and shelley-qa are supported for truncate-chain recipe"
    exit 1
  fi

  if ! [ -d "$STATEDIR/db-{{ENV}}/node" ]; then
    echo "Error: no chain state appears to exist for {{ENV}} at: $STATEDIR/db-{{ENV}}/node"
    exit 1
  fi

  echo "Truncating cardano-node chain for envrionment {{ENV}} to slot {{SLOT}}"
  just stop-node {{ENV}}
  mkdir -p "$STATEDIR"

  SYNTH_ARGS=(
    "--db" "$STATEDIR/db-{{ENV}}/node/"
    "cardano"
    "--config" "$STATEDIR/config/{{ENV}}/config.json"
  )

  TRUNC_ARGS=(
    "${SYNTH_ARGS[@]}"
    "--truncate-after-slot" "{{SLOT}}"
  )

  nix run .#job-gen-env-config &> /dev/null
  if [[ "{{ENV}}" =~ ^mainnet$|^preprod$|^preview$ ]]; then
    cp result/environments/config/{{ENV}}/*  "$STATEDIR/config/{{ENV}}/"
    chmod -R +w "$STATEDIR/config/{{ENV}}/"
    db-truncater "${TRUNC_ARGS[@]}"

    echo "Truncation finished."
    echo "Analyzing to confirm truncation.  This may take some time..."
    db-analyser "${SYNTH_ARGS[@]}"
  else
    cp result/environments-pre/config/{{ENV}}/*  "$STATEDIR/config/{{ENV}}/"
    chmod -R +w "$STATEDIR/config/{{ENV}}/"
    db-truncater-ng "${TRUNC_ARGS[@]}"

    echo "Truncation finished."
    echo "Analyzing to confirm truncation.  This may take some time..."
    db-analyser-ng "${SYNTH_ARGS[@]}"
  fi

  echo
  echo "Note that db-truncater does not produce exact results."
  echo "If the chain is still longer then you want, try reducing the truncation slot more."

# Update cluster ips from tofu
update-ips:
  #!/usr/bin/env nu
  nix build ".#opentofu.cluster" --out-link terraform.tf.json
  tofu init -reconfigure
  tofu workspace select -or-create cluster

  print "\n"
  let nodeCount = nix eval .#nixosConfigurations --raw --apply 'let f = x: toString (builtins.length (builtins.attrNames x)); in f'
  print $"Processing ip information for ($nodeCount) nixos machine configurations..."

  let tofuJson = (tofu show -json | from json)

  let eipRecords = ($tofuJson
    | get values.root_module.resources
    | where type == "aws_eip"
  )

  let instanceRecords = ($tofuJson
    | get values.root_module.resources
    | where type == "aws_instance"
  )

  let eipTable = ($eipRecords
    | select name values.private_ip values.public_ip
    | rename name private_ipv4 public_ipv4
  )

  let instanceTable = ($instanceRecords
    | select name values.ipv6_addresses
    | rename name public_ipv6
    | update public_ipv6 {|row| if ($row.public_ipv6 | is-not-empty) {$row.public_ipv6.0} else {null}}
  )

  let ipTable = ($eipTable | merge $instanceTable)

  ($ipTable
  | reduce --fold ["
    let
      all = {
    "]
    {|machine, acc|
      $acc | append $"
    ($machine.name) = {
      privateIpv4 = "($machine.private_ipv4)";
      publicIpv4 = "($machine.public_ipv4)";
      publicIpv6 = "($machine.public_ipv6)";
    };"
    }
  | append "
      };
    in {
      flake.nixosModules.ips = all;
      flake.nixosModules.ip-module = {
        name,
        lib,
        ...
      }: {
        options.ips = {
          privateIpv4 = lib.mkOption {
            type = lib.types.str;
            default = all.${name}.privateIpv4 or "";
          };
          publicIpv4 = lib.mkOption {
            type = lib.types.str;
            default = all.${name}.publicIpv4 or "";
          };
          publicIpv6 = lib.mkOption {
            type = lib.types.str;
            default = all.${name}.publicIpv6 or "";
          };
        };
      };
    }
    "
  | str join "\n"
  | alejandra --quiet -
  | save --force flake/nixosModules/ips-DONT-COMMIT.nix
  )

  # This is required for flake builds to find the nix module.
  # The pre-push git hook will complain if this file has been committed accidently.
  git add --intent-to-add flake/nixosModules/ips-DONT-COMMIT.nix

  print $"Ips were written for a machine count of: ($eipRecords | length)"
  if $nodeCount != ($eipRecords | length | into string) {
    print "\n"
    print $"(ansi bg_red)WARNING:(ansi reset) There are ($nodeCount) nixos machine configurations but ($eipRecords | length) ip record sets were written."
    print "\n"
  }

  print "Ips have been written to: flake/nixosModules/ips-DONT-COMMIT.nix"
  print "Obviously, don't commit this file."

# Generate example ip-module code
update-ips-example:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "The following code example shows the expected struct of the \"ips\" and \"ip-module\" nixosModules."
  echo "This may be used as a template if a custom flake/nixosModules/ips-DONT-COMMIT.nix file"
  echo "needs to be created and managed manually, for example, in a non-aws environment."
  echo
  echo "Note that the line ordering of privateIpv4, publicIpv4, publicIpv6 matters!"
  echo
  echo "---"
  echo
  cat <<"EOF"
  let
    all = {
      machine-example-1 = {
        privateIpv4 = "172.16.0.1";
        publicIpv4 = "1.2.3.4";
        publicIpv6 = "ff00::01";
      };

      machine-example-2 = {
        privateIpv4 = "172.16.0.2";
        publicIpv4 = "1.2.3.5";
        publicIpv6 = "";
      };
    };
  in {
    flake.nixosModules.ips = all;
    flake.nixosModules.ip-module = {
      name,
      lib,
      ...
    }: {
      options.ips = {
        privateIpv4 = lib.mkOption {
          type = lib.types.str;
          default = all.${name}.privateIpv4 or "";
        };
        publicIpv4 = lib.mkOption {
          type = lib.types.str;
          default = all.${name}.publicIpv4 or "";
        };
        publicIpv6 = lib.mkOption {
          type = lib.types.str;
          default = all.${name}.publicIpv6 or "";
        };
      };
    };
  }
  EOF
