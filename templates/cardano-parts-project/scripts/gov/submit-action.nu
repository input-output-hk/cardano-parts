#!/usr/bin/env nu
# Run from the repository root with the node environment sourced.
# Unknown flags are forwarded verbatim to `governance action <action>`.
# Default: build + sign; --dry-run only plans; --submit opts into submission.
# Guide: docs/explain/submit-action.md
const networks = {
  mainnet: "764824073"
  preprod: "1"
  preview: "2"
  sanchonet: "4"
  dijkstra: "6"
  leios: "164"
  demo: "42"
}
const actions = {
  pparams: "create-protocol-parameters-update"
  info: "create-info"
  hardfork: "create-hardfork"
  constitution: "create-constitution"
  committee: "update-committee"
  "no-confidence": "create-no-confidence"
  treasury: "create-treasury-withdrawal"
}
def fail [message: string]: nothing -> any { error make --unspanned {msg: $message} }
# Quote arguments for Bash, including paths containing apostrophes.
def shell-quote [value: string]: nothing -> string {
  if $value =~ '^[a-zA-Z0-9_./:=#-]+$' { return $value }
  "'" + ($value | str replace --all "'" "'\"'\"'") + "'"
}
# Both plaintext CLI envelopes and the repository's SOPS binary envelopes work.
# Private material is only written inside a mode-0700 temporary directory.
def key-file [source: string, tmp: string]: nothing -> string {
  if not ($source | path exists) { fail $"Key file not found: ($source)" }
  let doc = open --raw $source | from json
  if "sops" not-in ($doc | columns) { return ($source | path expand) }
  let dest = $tmp | path join (random uuid)
  ^just sops-decrypt-binary $source | save --raw $dest
  ^chmod 0600 $dest
  $dest
}
def choose-stake [node_env: string, explicit: string]: nothing -> string {
  if ($explicit | is-not-empty) { return $explicit }
  let candidates = glob $"secrets/groups/($node_env)*/no-deploy/*-owner-stake.vkey" | sort
  if ($candidates | is-empty) { fail "No deposit-return keys found; pass --stake-key <key stem>." }
  let selected = if ($candidates | length) == 1 {
    $candidates | first
  } else {
    $candidates | input list "Deposit return stake key:"
  }
  if ($selected | is-empty) { fail "No deposit-return key selected." }
  $selected | str replace --regex '\.vkey$' ''
}
def previous-hint [run: record]: nothing -> string {
  let purpose = match $run.action {
    create-protocol-parameters-update => 'PParamUpdate'
    create-hardfork => 'HardFork'
    create-constitution => 'Constitution'
    _ => 'Committee'
  }
  let cli = $run.cli
  let state = ^$cli $run.era query gov-state ...$run.net | from json
  let parents = $state | get nextRatifyState.nextEnactState.prevGovActionIds
  # Missing fields are errors, not evidence that this is the first action.
  if $purpose not-in ($parents | columns) { fail $"Governance state has no ($purpose) predecessor field." }
  let parent = $parents | get $purpose
  print $"Previous-action hint: nextRatifyState.nextEnactState.prevGovActionIds.($purpose)"
  if $parent == null {
    print $"  No previous ($purpose) action recorded; suggested value: none"
    return 'none'
  }
  let candidate = $"($parent.txId)#($parent.govActionIx)"
  if $candidate !~ '^[0-9a-fA-F]{64}#[0-9]+$' { fail "Unrecognized previous-action ID in governance state." }
  print $"  ($candidate)"
  let pending = $state | get proposals | any {|p| $p.actionId == $parent }
  if $pending {
    print "  This action is still in the proposals set: the hint comes from projected ratification state, not confirmed enactment."
  }
  $candidate
}
def previous-args [run: record, previous: string]: nothing -> list<string> {
  let action = $run.action
  if $action in [create-info, create-treasury-withdrawal] {
    if ($previous | is-not-empty) { fail "This action has no previous-action link." }
    return []
  }
  let previous = if ($previous | is-empty) {
    let hint = try { previous-hint $run } catch {|err|
      print -e $"Could not look up a predecessor hint: ($err.msg)"
      ''
    }
    let prompt = if ($hint | is-empty) {
      "Previous action of this purpose (TXID#INDEX, or 'none' for the first): "
    } else { $"Previous action [Enter accepts ($hint), or type an override]: " }
    let reply = input $prompt | str trim
    if ($reply | is-empty) { $hint } else { $reply }
  } else { $previous }
  if $previous == "none" { return [] }
  if $previous !~ '^[0-9a-fA-F]{64}#[0-9]+$' {
    fail "Pass --previous-action TXID#INDEX, or explicitly use 'none' for the first action of this purpose."
  }
  let parts = $previous | split row '#'
  if ($parts.1 | into int) > 65535 { fail "Previous action index exceeds WORD16." }
  [
    --prev-governance-action-tx-id
    $parts.0
    --prev-governance-action-index
    $parts.1
  ]
}
# Create a governance action using native cardano-cli action flags.
#
# Examples (Bash):
#   submit-action.nu leios pparams --anchor-url ipfs://CID \
#     --previous-action none --max-endorser-block-txs-size 2000000 \
#     --max-endorser-block-references-size 308000 --dry-run
#   submit-action.nu preview info --anchor-url ipfs://CID --submit
#
# Without --previous-action, query the same purpose's predecessor and offer it
# at the prompt. Projected predecessors still in the proposals set are labeled.
def --wrapped main [
  node_env: string = ""                 # Environment from just set-default-cardano-env
  action: string = "pparams"            # pparams|info|hardfork|constitution|committee|no-confidence|treasury, or full CLI name
  --anchor-url: string = ""             # Published rationale URL or bare IPFS CID (required)
  --anchor-hash: string = ""            # Optional expected hash; checked against fetched bytes
  --rationale-file: path = ""           # Optional local document; must match the published bytes
  --payment-key: string = ""            # Key stem; defaults to secrets/envs/<env>/utxo-keys/rich-utxo
  --stake-key: string = ""              # Deposit return key stem; otherwise choose an owner key
  --previous-action: string = ""        # TXID#INDEX or 'none'; otherwise query a hint and prompt
  --guardrails-file: path = ""          # Script matching the live constitution; otherwise discover in docs
  --guardrails-redeemer: path = ""      # Optional JSON redeemer file; default is {}
  --cli: string = "cardano-cli"         # Use the Leios-pinned CLI for leios
  --out-dir: path = ""                 # New directory for action, tx, rationale and Markdown report
  --dry-run                            # Query and show plan; do not decrypt keys, build, sign or submit
  --submit                             # Submit after review (default is build + sign only)
  --yes                                # Skip submission confirmation; still requires --submit
  --help (-h)                          # Show usage
  ...action_args: string                # Native action flags, passed without shell evaluation
]: nothing -> nothing {
  if $help {
    print (help main)
    return
  }
  let extra = $env.EXTRA_ENV_MAGIC? | default '{}' | from json
  let magics = $networks | merge $extra
  if $node_env not-in ($magics | columns) { fail $"Unknown environment: ($node_env)" }
  let magic = $magics | get $node_env | into string
  if ($env.TESTNET_MAGIC? | default '' | into string) != $magic {
    fail $"Source the ($node_env) node environment first: source <\(just set-default-cardano-env ($node_env)\)"
  }
  if ($env.CARDANO_NODE_SOCKET_PATH? | is-empty) { fail "CARDANO_NODE_SOCKET_PATH is unset." }
  if $dry_run and $submit { fail "Choose --dry-run or --submit, not both." }
  let command = $actions | get -o $action | default $action
  if $command not-in ($actions | values) { fail $"Unsupported action: ($action)" }
  # These are managed here, so an accidental duplicate cannot override review.
  let reserved = [
    --out-file
    --mainnet
    --testnet
    --governance-action-deposit
    --deposit-return-stake-verification-key-file
    --deposit-return-stake-key-hash
    --deposit-return-stake-address
    --anchor-url
    --anchor-data-hash
    --prev-governance-action-tx-id
    --prev-governance-action-index
  ]
  for arg in $action_args {
    if ($arg | split row '=' | first) in $reserved { fail $"Managed flag ($arg): use this tool's options instead." }
    if $command in [create-protocol-parameters-update, create-treasury-withdrawal] and ($arg | split row '=' | first) == '--constitution-script-hash' {
      fail "The constitution script hash is read from the live chain; use --guardrails-file."
    }
  }
  if ($anchor_url | is-empty) { fail "--anchor-url is required (published CIP-108 rationale)." }
  let url = if $anchor_url =~ '^[a-zA-Z][a-zA-Z0-9+.-]*://' { $anchor_url } else { $"ipfs://($anchor_url)" }
  let net = if $node_env == 'mainnet' { [--mainnet] } else { [--testnet-magic, $magic] }
  let action_net = if $node_env == 'mainnet' { [--mainnet] } else { [--testnet] }
  let tip = ^$cli query tip ...$net | from json
  if ($tip.syncProgress? | default '0' | into float) < 100 { fail "Node is not fully synced; wait before preparing the action." }
  let era = $tip.era | str downcase
  if $era not-in [conway, dijkstra] { fail $"Unsupported governance era: ($era)" }
  ^$cli $era governance action $command --help | ignore
  let pparams = ^$cli $era query protocol-parameters ...$net | from json
  let deposit = $pparams.govActionDeposit | into string
  let parent = previous-args {
    action: $command
    cli: $cli
    era: $era
    net: $net
  } $previous_action
  let payer = if ($payment_key | is-empty) { $"secrets/envs/($node_env)/utxo-keys/rich-utxo" } else { $payment_key }
  let stake = choose-stake $node_env $stake_key
  for file in [
    $"($payer).vkey"
    $"($payer).skey"
    $"($stake).vkey"
  ] {
    if not ($file | path exists) { fail $"Key file not found: ($file)" }
  }
  let tmp = ^mktemp --directory | str trim
  ^chmod 0700 $tmp
  try {
    let gateway = $env.IPFS_GATEWAY_URI? | default 'https://gateway.pinata.cloud' | str trim --right --char '/'
    $env.IPFS_GATEWAY_URI = $gateway
    let fetch_url = if ($url | str starts-with 'ipfs://') { $"($gateway)/ipfs/($url | str substring 7..)" } else { $url }
    if $fetch_url !~ '^https?://' { fail "Rationale must use https://, http:// or ipfs://." }
    let metadata = $tmp | path join 'rationale.json'
    ^curl --fail --location --silent --show-error --max-time 60 $fetch_url --output $metadata
    let doc = open --raw $metadata | from json
    for field in [title, abstract, motivation, rationale] {
      if ($doc | get -o body | get -o $field | is-empty) { fail $"Proposal rationale is missing body.($field); use a CIP-108 proposal document." }
    }
    let hash = ^$cli hash anchor-data --file-binary $metadata | str trim
    if ($anchor_hash | is-not-empty) and ($anchor_hash | str downcase) != $hash { fail "Published rationale does not match --anchor-hash." }
    if ($rationale_file | is-not-empty) {
      let local_hash = ^$cli hash anchor-data --file-binary $rationale_file | str trim
      if $local_hash != $hash { fail "Published rationale differs from --rationale-file." }
    }
    mut guard = ''
    mut policy = ''
    if $command in [create-protocol-parameters-update, create-treasury-withdrawal] {
      let constitution = ^$cli $era query constitution ...$net | from json
      if 'script' not-in ($constitution | columns) { fail "Unrecognized constitution JSON: expected the script field." }
      $policy = ($constitution.script | default '')
      if ($policy | is-not-empty) {
        let candidates = if ($guardrails_file | is-not-empty) { [$guardrails_file] } else {
          [
            $"docs/environments/($node_env)/guardrails-script.plutus"
            $"docs/environments-pre/($node_env)/guardrails-script.plutus"
          ]
        }
        for candidate in $candidates {
          if ($candidate | path exists) {
            let candidate_hash = ^$cli $era transaction policyid --script-file $candidate | str trim
            if $candidate_hash == $policy {
              $guard = ($candidate | path expand)
              break
            }
          }
        }
        if ($guard | is-empty) { fail $"Provide --guardrails-file matching the live constitution hash ($policy)." }
      }
    }
    print $"\n(ansi green_bold)($node_env): ($command)(ansi reset)"
    print {era: $era, epoch: $tip.epoch, deposit_ADA: (($deposit | into int) / 1000000), payment_key: $payer, deposit_return_key: $stake, anchor: $url, anchor_hash: $hash, guardrails: $guard, previous: ($parent | to nuon), changes: ($action_args | to nuon)}
    if $command == 'create-protocol-parameters-update' {
      let eb = $pparams | select -o maxEndorserBlockTxsSize maxEndorserBlockReferencesSize
      if ($eb | is-not-empty) {
        print "Current EB limits:"
        print $eb
      }
    }
    if $dry_run {
      print "Dry run complete: no keys decrypted and no transaction built."
    } else {
      let output = if ($out_dir | is-empty) {
        $"workbench/gov-actions/($node_env)-($action)-(date now | format date '%Y%m%dT%H%M%S')-(random uuid | str substring 0..7)"
      } else {
        $out_dir | into string
      }
      if ($output | path exists) { fail $"Output directory already exists: ($output)" }
      mkdir $output
      let output = $output | path expand
      let action_file = $output | path join 'proposal.action'
      let body = $output | path join 'transaction.txbody'
      let signed = $output | path join 'transaction.txsigned'
      cp $metadata ($output | path join 'rationale.json')
      $pparams | to json | save ($output | path join 'protocol-parameters.json')
      let payment_vkey = key-file $"($payer).vkey" $tmp
      let return_vkey = key-file $"($stake).vkey" $tmp
      let policy_args = if ($policy | is-empty) { [] } else { [--constitution-script-hash, $policy] }
      ^$cli $era governance action $command ...$action_net --governance-action-deposit $deposit --deposit-return-stake-verification-key-file $return_vkey --anchor-url $url --anchor-data-hash $hash ...$parent ...$policy_args ...$action_args --out-file $action_file
      print "Proposal:"
      ^$cli $era governance action view --action-file $action_file
      print ""
      let address = ^$cli address build --payment-verification-key-file $payment_vkey ...$net | str trim
      let utxos = ^$cli $era query utxo --address $address ...$net --output-json | from json
      # Choose ADA-only inputs: avoid spending tokens, inline datums or reference scripts.
      let available = $utxos | transpose txin output | where {|u|
        ($u.output.value | columns) == [lovelace] and ($u.output.inlineDatum? | is-empty) and ($u.output.datumhash? | is-empty) and ($u.output.referenceScript? | is-empty)
      } | sort-by { |u| $u.output.value.lovelace } --reverse
      if ($available | is-empty) { fail "No plain ADA funding UTxO available." }
      let funding = $available | first
      if $funding.output.value.lovelace <= ($deposit | into int) { fail "Largest plain ADA UTxO cannot cover the deposit plus fees; consolidate/refill the payer." }
      mut script_args = []
      if ($guard | is-not-empty) {
        let collateral = $available | skip 1 | where {|u| $u.output.value.lovelace >= 10000000 } | last 1
        if ($collateral | is-empty) { fail "Guardrails need a separate plain ADA collateral UTxO of at least 10 ADA." }
        let script_copy = $output | path join 'guardrails.plutus'
        cp $guard $script_copy
        let redeemer = if ($guardrails_redeemer | is-empty) { [--proposal-redeemer-value, '{}'] } else {
          let dest = $output | path join 'redeemer.json'
          cp $guardrails_redeemer $dest
          [--proposal-redeemer-file, $dest]
        }
        $script_args = ([
          --tx-in-collateral
          ($collateral | first | get txin)
          --proposal-script-file
          $script_copy
        ] | append $redeemer)
      }
      ^$cli $era transaction build ...$net --tx-in $funding.txin --change-address $address --witness-override 1 --proposal-file $action_file ...$script_args --out-file $body
      print "Transaction review:"
      ^$cli debug transaction view --tx-body-file $body
      let payment_skey = key-file $"($payer).skey" $tmp
      ^$cli $era transaction sign --tx-body-file $body --signing-key-file $payment_skey ...$net --out-file $signed
      # Signing is the last use of decrypted keys. Do not retain them while
      # waiting for interactive confirmation or submitting the signed file.
      rm --recursive --force --permanent $tmp
      let id_output = ^$cli $era transaction txid --tx-file $signed | str trim
      let txid = if $id_output =~ '^\{' {
        $id_output | from json | get txhash
      } else {
        $id_output | str trim --char '"'
      }
      let report = $"# Governance action\n\n- Network: ($node_env)\n- Era: ($era)\n- Action: ($command)\n- Deposit: ($deposit) lovelace\n- Deposit return key: ($stake)\n- Rationale: ($url)\n- Anchor hash: ($hash)\n- Action ID: ($txid)#0\n- Arguments: ($action_args | to json --raw)\n- Previous action arguments: ($parent | to json --raw)\n- Status: built and signed; not submitted\n"
      let report_path = $output | path join 'README.md'
      let cli_path = which $cli | first | get path | path expand
      let socket = $env.CARDANO_NODE_SOCKET_PATH | path expand
      let submit_command = ([
        env
        $"CARDANO_NODE_SOCKET_PATH=($socket)"
        $cli_path
        $era
        transaction
        submit
      ] | append $net | append [--tx-file, $signed] | each {|arg| shell-quote $arg } | str join ' ')
      let report = $report + $"\n## Submit this transaction\n\n```bash\n($submit_command)\n```\n"
      $report | save $report_path
      print $"\nSaved: ($output)\nAction ID: ($txid)#0"
      print $"\nSubmit this signed transaction \(Bash\):\n($submit_command)\n"
      if $submit {
        let confirmed = if $yes { true } else { (input $"Submit to ($node_env), locking ($deposit) lovelace? [y/N] " | str trim | str downcase) in [y, yes] }
        if $confirmed {
          ^$cli $era transaction submit ...$net --tx-file $signed
          $report | str replace 'built and signed; not submitted' 'submission accepted by node; on-chain confirmation pending' | save --force $report_path
          print $"Submission accepted. Check confirmation before voting on ($txid)#0."
        } else { print "Not submitted. Signed transaction retained." }
      } else { print "Not submitted. Use the command above to submit this signed transaction." }
    }
  } catch {|err|
    rm --recursive --force --permanent $tmp
    error make $err.raw
  }
  rm --recursive --force --permanent $tmp
}
