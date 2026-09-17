#!/usr/bin/env nu
# Unified interactive governance voting tool
#
# Replaces the per-role voting scripts (vote-with-cc.sh,
# vote-with-pools-and-drep.sh) with a single, env-aware flow. It discovers the
# voters available for an environment, walks you through them interactively
# ("vote with cc2? drep-0? preview1-bp-a-1?"), collects a yes/no/abstain
# decision for each, and then assembles and submits the vote transaction(s).
#
# Two CC mechanisms exist in this repo and are auto-detected per environment:
#
#   * orchestrator multisig  (preprod, preview): cc, cc2, ... cc7 directories
#       under secrets/envs/$ENV/cc-keys/. Each member spends its hot-NFT UTxO
#       with Plutus scripts and is witnessed by 3 voter keys + the orchestrator.
#       These cannot be merged with ordinary votes, so each gets its own tx.
#
#   * simple hot keys        (leios, dijkstra): cc-1-hot, cc-2-hot, cc-3-hot.
#       A plain `governance vote create --cc-hot-verification-key-file`, freely
#       combinable with drep/pool votes in one transaction.
#
# Assembly rule (matches the agreed design): everything combinable
# (simple-CC + drep + pools) goes into ONE transaction; each orchestrator-CC
# vote is emitted as its own separate transaction.
#
# USAGE (run from the repo root inside the playground devShell):
#
#   # Source the node env first so the socket + magic are available:
#   source <(just set-default-cardano-env preview)
#
#   scripts/gov/vote.nu preview <action-tx-id> <action-idx>
#   scripts/gov/vote.nu preview <action-tx-id> 0 --decision yes
#   scripts/gov/vote.nu preview <action-tx-id> 0 --anchor-url ipfs://...
#   scripts/gov/vote.nu leios  <action-tx-id> 0 --dry-run
#
# The --decision flag sets the default offered at each per-voter prompt
# (still overridable inline). --anchor-url supplies the CC voting rationale
# anchor (required for orchestrator-CC votes; optional otherwise) — or instead
# pass --rationale-file <doc> (with --blockfrost-project-id / $env.BLOCKFROST_IPFS_PROJECT_ID)
# to have the tool sign (CIP-100 author = $env.CC_RATIONALE_AUTHOR, default
# "CC member") + upload the rationale to IPFS (via rationale.nu) and use the
# resulting anchor automatically. When --anchor-hash is omitted, the hash is fetched from
# the anchor URL via $env.IPFS_GATEWAY_URI (defaults to https://ipfs.io).
#
# Submission is opt-in: by default the tool builds + signs and writes the signed
# tx(s) to the working dir WITHOUT submitting. Pass --submit to submit (still
# prompts per tx unless --yes is also given). --dry-run discovers + prompts +
# reports the plan but builds nothing.
#
# By default only CC members whose hot credential is currently MemberAuthorized
# and Active on-chain (per committee-state) are offered, so retired/never-hot
# members (e.g. cc4+) are filtered out; pass --include-inactive-cc to override.
#
# For orchestrator-CC votes the per-member orchestrator payment address pays the
# fee on every vote, so its remaining balance is printed before each such tx
# (also during --dry-run) and a LOW BALANCE warning fires below --orch-warn-ada
# (default 10 ADA) so it can be refilled before it runs dry.
#
# DEPENDENCIES: just (sops-decrypt-binary), cardano-cli (or cardano-cli-ng),
# jq, and for orchestrator-CC: orchestrator-cli. All provided by the devShell.
# Baked-in Cardano network magics: the public networks, the iohk-nix testnets
# (dijkstra, leios), and the default local cluster (demo). These are standard
# enough to live here (dijkstra/leios come from iohk-nix and are heading into
# the cardano book). Additional downstream-only envs are supplied via the
# EXTRA_ENV_MAGIC env var (a JSON object of "<env>: <magic>" pairs), typically
# exported from custom.just, e.g.: export EXTRA_ENV_MAGIC := '{"myenv":"999"}'
const std_env_magic = {
  mainnet: "764824073"
  preprod: "1"
  preview: "2"
  sanchonet: "4"
  dijkstra: "6"
  leios: "164"
  demo: "42"
}
# Env -> testnet magic, merging the standard networks with any downstream extras.
# Used to verify the sourced node env matches the env being voted on, and (via
# its keys) as the accepted-env allow-list. Matches checkEnvWithoutOverride in
# the Justfile.
def env-magic []: nothing -> record {
  let extra = ($env.EXTRA_ENV_MAGIC? | default "" | str trim)
  if ($extra | is-empty) { $std_env_magic } else {
    $std_env_magic | merge ($extra | from json)
  }
}
# ─── small helpers ──────────────────────────────────────────────────────────
# Pick the cardano-cli binary the rest of the repo would pick for this env.
# Mirrors the selectCardanoCli logic in the Justfile/governance.just. `nenv` is
# the node-env name (not the $env record).
def select-cli [nenv: string, override: string] {
  if ($override | is-not-empty) { return $override }
  let unstable = ($env.UNSTABLE? | default "")
  if ($env.USE_SHELL_BINS? | default "") == "true" {
    "cardano-cli"
  } else if ($unstable != "" and $unstable != "true") {
    "cardano-cli"
  } else if $unstable == "true" {
    "cardano-cli-ng"
  } else if ($nenv in (["mainnet", "preprod", "preview", "leios"] | append ($env.STABLE_CLI_ENVS? | default "" | split row " " | where {|e| $e != ""}))) {
    "cardano-cli"
  } else {
    "cardano-cli-ng"
  }
}
# Decrypt a sops-encrypted secret to a 0600 file inside the run's temp dir and
# return its path. Cached by relative path so repeated lookups only decrypt
# once.
def secret-file [run: record, rel: string]: nothing -> string {
  let dest = ($run.tmp | path join ($rel | str replace --all '/' '_'))
  if not ($dest | path exists) {
    ^just sops-decrypt-binary $rel | save --raw --force $dest
    chmod 0600 $dest
  }
  $dest
}
# Decrypt a sops-encrypted secret and return its trimmed contents as a string
# (for addresses, hashes, token names, etc.).
def secret-str [rel: string]: nothing -> string {
  ^just sops-decrypt-binary $rel | into string | str trim
}
# Yes/No gate. Returns true only on an explicit y/yes. `auto` marks pure
# confirmation prompts that --yes is allowed to auto-approve.
def ask-yn [prompt: string, auto: bool, yes: bool]: nothing -> bool {
  if $auto and $yes { return true }
  let reply = (input $"($prompt) [yN] ")
  ($reply | str downcase | str trim) in [y, yes]
}
# Prompt for a yes/no/abstain decision, defaulting to `dflt`.
def ask-decision [who: string, dflt: string] {
  loop {
    let reply = (input $"  Decision for (ansi cyan)($who)(ansi reset) [yes/no/abstain] \(default ($dflt)\): " | str trim | str downcase)
    let val = (if ($reply | is-empty) { $dflt } else { $reply })
    if $val in [yes, no, abstain] { return $val }
    print $"  (ansi red)Please answer yes, no or abstain.(ansi reset)"
  }
}
# Map a decision to the cardano-cli vote flag.
def decision-flag [decision: string] { match $decision {
  yes => "--yes"
  no => "--no"
  abstain => "--abstain"
  _ => { error make --unspanned {
    msg: $"invalid decision: ($decision)"
  } }
} }
# ─── voter discovery ──────────────────────────────────────────────────────────
# "orchestrator", "simple" or "none" depending on what cc-keys layout the env
# has on disk.
def detect-cc-mode [nenv: string]: nothing -> string {
  let base = $"secrets/envs/($nenv)/cc-keys"
  if not ($base | path exists) { return "none" }
  if (glob $"($base)/cc*/orchestrator.addr" | is-not-empty) {
    "orchestrator"
  } else if (glob $"($base)/cc-*-hot.vkey" | is-not-empty) {
    "simple"
  } else {
    "none"
  }
}
# Discover CC voters. For orchestrator envs each entry is a member directory
# name (cc, cc2, ...); for simple envs each entry is a key stem (cc-1, ...).
def discover-cc [nenv: string, mode: string]: nothing -> list<any> {
  let base = $"secrets/envs/($nenv)/cc-keys"
  match $mode {
    "orchestrator" => {
      glob $"($base)/cc*/orchestrator.addr" | each {|p| $p | path dirname | path basename } | sort --natural
    }
    "simple" => {
      glob $"($base)/cc-*-hot.vkey" | each {|p| $p | path basename | str replace '-hot.vkey' '' } | sort --natural
    }
    _ => []
  }
}
# Discover DRep key stems (drep-0, ...).
def discover-dreps [nenv: string]: nothing -> list<any> {
  glob $"secrets/envs/($nenv)/drep/drep-*.vkey" | each {|p| $p | path basename | str replace '.vkey' '' } | sort --natural
}
# Discover stake-pool voters: any deploy cold vkey with a matching no-deploy
# cold skey, across all groups belonging to this env. Returns rows with the
# pool name plus resolved vkey/skey relative paths.
def discover-pools [nenv: string]: nothing -> table {
  glob $"secrets/groups/($nenv)*/deploy/*-cold.vkey" | each {|vkey|
        let group = ($vkey | path dirname | path dirname | path basename)
        let name = ($vkey | path basename | str replace '-cold.vkey' '')
        let skey = $"secrets/groups/($group)/no-deploy/($name)-cold.skey"
        if ($skey | path exists) {
          {name: $name, group: $group, vkey: $vkey, skey: $skey}
        } else {
          null
        }
      } | compact | sort-by name
}
# The hot-credential hashes (keyHash or scriptHash) that are currently
# authorized AND active on the constitutional committee, per committee-state.
def active-hot-hashes [run: record] {
  let cli = $run.cli
  let cs = (^$cli latest query committee-state --testnet-magic $run.magic | from json)
  $cs.committee | values | where {|m| ($m.hotCredsAuthStatus?.tag? == "MemberAuthorized") and ($m.status? == "Active") } | each {|m| ($m.hotCredsAuthStatus.contents.keyHash? | default ($m.hotCredsAuthStatus.contents.scriptHash?)) } | compact
}
# The on-chain hot-credential hash for a CC member. For orchestrator members
# this is the hot credential script hash; for simple members it is the hot key
# hash derived from the verification key.
def cc-hot-hash [run: record, mode: string, name: string] {
  if $mode == "orchestrator" {
    secret-str $"secrets/envs/($run.env)/cc-keys/($name)/init-hot/credential.plutus.hash"
  } else {
    let cli = $run.cli
    (^$cli latest governance committee key-hash --verification-key-file (secret-file $run $"secrets/envs/($run.env)/cc-keys/($name)-hot.vkey")) | into string | str trim
  }
}
# Drop CC members whose hot credential is not currently active on-chain (so
# retired/never-hot members like cc4+ are not offered), unless the operator
# passed --include-inactive-cc. Prints what was skipped/included.
def filter-active-cc [run: record, mode: string, ccs: list<any>] {
  if ($ccs | is-empty) { return $ccs }
  let active = (active-hot-hashes $run)
  let rows = ($ccs | each {|c| {name: $c, hot_active: ((cc-hot-hash $run $mode $c) in $active)} })
  let inactive = ($rows | where {|r| not $r.hot_active } | get name)
  if ($inactive | is-not-empty) {
    if $run.include_inactive_cc {
      print $"(ansi yellow)Including hot-INACTIVE CC members \(--include-inactive-cc\): ($inactive | str join ', ')(ansi reset)"
    } else {
      print $"(ansi dark_gray)Skipping hot-inactive CC members \(use --include-inactive-cc to offer anyway\): ($inactive | str join ', ')(ansi reset)"
    }
  }
  if $run.include_inactive_cc { $ccs } else {
    $rows | where {|r| $r.hot_active } | get name
  }
}
# ─── node / gov-action queries ────────────────────────────────────────────────
# Verify the sourced node env is present AND matches the env being voted on,
# then return the (verified) testnet magic. Guards against sourcing one env and
# voting on another (which would query one network but build from another env's
# secrets). Mirrors the env/magic handling in the Justfile recipes.
def require-node-env [nenv: string, expected_magic: string]: nothing -> string {
  for v in [CARDANO_NODE_SOCKET_PATH, TESTNET_MAGIC] {
    if ($env | get -o $v | is-empty) {
      error make --unspanned {
        msg: $"($v) is not set. Run: source <\(just set-default-cardano-env ($nenv)\)"
      }
    }
  }
  if $env.TESTNET_MAGIC != $expected_magic {
    error make --unspanned {
      msg: $"Loaded TESTNET_MAGIC=($env.TESTNET_MAGIC) does not match env ($nenv) \(expected ($expected_magic)\). Re-source: source <\(just set-default-cardano-env ($nenv)\)"
    }
  }
  # Best-effort: set-default-cardano-env links node.socket -> node-<env>.socket,
  # so if the socket resolves to a different env's socket, the wrong env is live.
  let target = (try {
    $env.CARDANO_NODE_SOCKET_PATH | path expand
  } catch { $env.CARDANO_NODE_SOCKET_PATH })
  let tname = ($target | path basename)
  if ($tname | str starts-with "node-") and ($tname | str ends-with ".socket") and ($tname != $"node-($nenv).socket") {
    error make --unspanned {
      msg: $"Socket ($env.CARDANO_NODE_SOCKET_PATH) resolves to ($tname), not node-($nenv).socket — wrong env sourced? Re-source: source <\(just set-default-cardano-env ($nenv)\)"
    }
  }
  $expected_magic
}
def gov-action-state [run: record]: nothing -> any {
  let cli = $run.cli
  let state = (^$cli latest query gov-state --testnet-magic $run.magic | from json)
  $state.proposals | where {|p| $p.actionId.txId == $run.action_id and $p.actionId.govActionIx == $run.action_idx } | get -o 0
}
def require-synced [run: record]: nothing -> nothing {
  let cli = $run.cli
  let tip = (^$cli latest query tip --testnet-magic $run.magic | from json)
  if ($tip.syncProgress? | default "0") != "100.00" {
    error make --unspanned {
      msg: $"Environment ($run.env) is not fully synced \(syncProgress=($tip.syncProgress?)\). Wait for 100.00 before voting."
    }
  }
}
# Submit a signed tx file and wait until it clears the mempool.
def submit-and-watch [run: record, signed: string]: nothing -> nothing {
  let cli = $run.cli
  let txid = (^$cli latest transaction txid --tx-file $signed | from json | get txhash)
  print $"Submitting (ansi green)($signed)(ansi reset) with txid ($txid)..."
  ^$cli latest transaction submit --testnet-magic $run.magic --tx-file $signed
  mut exists = true
  while $exists {
    let r = (try {
      ^$cli latest query tx-mempool tx-exists $txid --testnet-magic $run.magic | from json | get exists
    } catch { false })
    $exists = $r
    if $exists {
      print $"  Still in mempool, sleeping 5s: ($txid)"
      sleep 5sec
    } else {
      print "  Removed from the mempool."
    }
  }
  print $"Transaction ($txid) submitted successfully.\n"
}
# Vote-count summary for an action's gov-state entry.
def vote-counts [action]: nothing -> record { {
  committee: (
    $action.committeeVotes? | default {} | columns | length
  )
  drep: (
    $action.dRepVotes? | default {} | columns | length
  )
  pool: (
    $action.stakePoolVotes? | default {} | columns | length
  )
} }
# Build/sign artifact review + optional submit.
def review-and-submit [run: record, label: string, signed: string]: nothing -> nothing {
  let cli = $run.cli
  print $"\n(ansi green_bold)── ($label) ──(ansi reset)"
  print "Transaction debug view:"
  ^$cli debug transaction view --tx-file $signed
  print ""
  # Submission is opt-in: without --submit we only build + sign. The signed tx
  # lives in the temp dir that cleanup removes, so copy it to the working dir
  # (it contains no secrets) and point the operator there.
  if not $run.submit {
    let slug = ($label | str downcase | str replace --all --regex '[^a-z0-9]+' '-' | str trim --char '-')
    let dest = ((pwd) | path join $"vote-($run.env)-($slug).txsigned")
    cp $signed $dest
    print $"(ansi yellow)Built and signed; not submitting \(pass --submit to submit\).(ansi reset)"
    print $"  Signed tx: (ansi green)($dest)(ansi reset)"
    print $"  Submit later with: ($cli) latest transaction submit --testnet-magic ($run.magic) --tx-file ($dest)"
    return
  }
  if not (ask-yn $"Submit ($label) to the ($run.env) network?" true $run.yes) {
    print $"(ansi yellow)Skipped submitting ($label).(ansi reset) Signed tx: ($signed)"
    return
  }
  let before = (gov-action-state $run)
  submit-and-watch $run $signed
  let after = (gov-action-state $run)
  print "Vote counts before -> after this submission:"
  print {before: (vote-counts $before), after: (vote-counts $after)}
}
# ─── selection (interactive prompts) ──────────────────────────────────────────
# Walk the discovered voters and return the operator's selections as a record
# of four lists. Orchestrator vs simple CC are kept separate because they
# assemble differently.
def collect-selections [
  run: record
  cc_mode: string
  ccs: list<any>
  dreps: list<any>
  pools: table
]: nothing -> record {
  mut sel = {
    simple_cc: []
    orch_cc: []
    drep: []
    pool: []
  }
  let dflt = $run.decision
  # ── Constitutional Committee ──
  if ($ccs | is-not-empty) {
    print $"\n(ansi blue_bold)Constitutional Committee(ansi reset) \(($cc_mode) mode\): ($ccs | str join ', ')"
    if (ask-yn "Vote with any CC members?" false $run.yes) {
      for cc in $ccs {
        if (ask-yn $"  Vote with CC member (ansi cyan)($cc)(ansi reset)?" false $run.yes) {
          let d = (ask-decision $cc $dflt)
          if $cc_mode == "orchestrator" {
            $sel.orch_cc = ($sel.orch_cc | append {name: $cc, decision: $d})
          } else {
            $sel.simple_cc = ($sel.simple_cc | append {name: $cc, decision: $d})
          }
        }
      }
    }
  } else {
    print $"\n(ansi dark_gray)No CC voters discovered for ($run.env).(ansi reset)"
  }
  # ── DReps ──
  if ($dreps | is-not-empty) {
    print $"\n(ansi blue_bold)DReps(ansi reset): ($dreps | str join ', ')"
    if (ask-yn "Vote with any DReps?" false $run.yes) {
      for d in $dreps {
        if (ask-yn $"  Vote with DRep (ansi cyan)($d)(ansi reset)?" false $run.yes) {
          $sel.drep = ($sel.drep | append {name: $d, decision: (ask-decision $d $dflt)})
        }
      }
    }
  } else {
    print $"\n(ansi dark_gray)No DRep voters discovered for ($run.env).(ansi reset)"
  }
  # ── Stake Pools ──
  if ($pools | is-not-empty) {
    print $"\n(ansi blue_bold)Stake Pools(ansi reset): ($pools.name | str join ', ')"
    if (ask-yn "Vote with any pools?" false $run.yes) {
      for p in $pools {
        if (ask-yn $"  Vote with pool (ansi cyan)($p.name)(ansi reset)?" false $run.yes) {
          $sel.pool = ($sel.pool | append ($p | merge {decision: (ask-decision $p.name $dflt)}))
        }
      }
    }
  } else {
    print $"\n(ansi dark_gray)No pool voters discovered for ($run.env).(ansi reset)"
  }
  $sel
}
# ─── transaction assembly ─────────────────────────────────────────────────────
# Select the smallest pure-lovelace UTxO > 5 ADA at an address (matches the
# selection used by the existing pool/drep voting script).
def pick-funding-utxo [run: record, addr: string]: nothing -> string {
  let cli = $run.cli
  let utxos = (^$cli latest query utxo --address $addr --testnet-magic $run.magic --output-json | from json)
  let chosen = (
    $utxos | transpose key value | where {|r| ($r.value.value | columns | length) == 1 and ($r.value.value.lovelace? | default 0) > 5000000 } | sort-by {|r| $r.value.value.lovelace } | get -o 0
  )
  if ($chosen | is-empty) {
    error make --unspanned {
      msg: $"No suitable funding UTxO \(pure lovelace > 5 ADA\) found at ($addr)."
    }
  }
  $chosen.key
}
# Build + sign the one combined tx for simple-CC + drep + pool votes.
# Returns the path to the signed tx, or null if there was nothing to combine.
def assemble-combined [run: record, sel: record]: nothing -> any {
  let cli = $run.cli
  let votes = ([
    ($sel.simple_cc | each {|v| {role: $v.name, vkey: $"secrets/envs/($run.env)/cc-keys/($v.name)-hot.vkey", skey: $"secrets/envs/($run.env)/cc-keys/($v.name)-hot.skey", flag: "--cc-hot-verification-key-file", decision: $v.decision}})
    ($sel.drep | each {|v| {role: $v.name, vkey: $"secrets/envs/($run.env)/drep/($v.name).vkey", skey: $"secrets/envs/($run.env)/drep/($v.name).skey", flag: "--drep-verification-key-file", decision: $v.decision}})
    ($sel.pool | each {|v| {role: $v.name, vkey: $v.vkey, skey: $v.skey, flag: "--cold-verification-key-file", decision: $v.decision}})
  ] | flatten)
  if ($votes | is-empty) { return null }
  print $"\n(ansi blue)Assembling combined tx for ($votes | length) vote\(s\): ($votes.role | str join ', ')(ansi reset)"
  # Create each vote file.
  let vote_files = ($votes | each {|v|
    let out = ($run.tmp | path join $"($v.role).vote")
    (^$cli latest governance vote create
      (decision-flag $v.decision)
      --governance-action-tx-id $run.action_id
      --governance-action-index $run.action_idx
      $v.flag (secret-file $run $v.vkey)
      --out-file $out)
    $out
  })
  if $run.dry_run {
    print $"(ansi yellow)[dry-run] would build combined tx with vote files:(ansi reset) ($vote_files | str join ', ')"
    return null
  }
  let rich_addr = (secret-str $"secrets/envs/($run.env)/utxo-keys/rich-utxo.addr")
  let txin = (pick-funding-utxo $run $rich_addr)
  let witnesses = (($votes | length) + 1)
  let body = ($run.tmp | path join "combined-vote.txbody")
  let build_args = ($vote_files | each {|f| [--vote-file $f] } | flatten)
  (^$cli latest transaction build --tx-in $txin --change-address $rich_addr --testnet-magic $run.magic --witness-override $witnesses ...$build_args --out-file $body)
  let signed = ($run.tmp | path join "combined-vote.txsigned")
  let sign_args = ([
    [
      --signing-key-file
      (secret-file $run $"secrets/envs/($run.env)/utxo-keys/rich-utxo.skey")
    ]
    ($votes | each {|v| [--signing-key-file (secret-file $run $v.skey)] } | flatten)
  ] | flatten)
  (^$cli latest transaction sign --tx-body-file $body --testnet-magic $run.magic ...$sign_args --out-file $signed)
  $signed
}
# Resolve the anchor (and optional precomputed hash) for orchestrator-CC votes.
# Priority: explicit --anchor-url; else sign+upload --rationale-file via
# rationale.nu. Does no signing/upload during --dry-run.
def resolve-orch-anchor [run: record] {
  if $run.dry_run {
    let url = (if ($run.anchor_url | is-not-empty) {
      $run.anchor_url
    } else if ($run.rationale_file | is-not-empty) {
      $"\(would prepare from ($run.rationale_file)\)"
    } else {
      ""
    })
    return {
      url: $url
      hash: ""
    }
  }
  if ($run.anchor_url | is-not-empty) {
    return {
      url: $run.anchor_url
      hash: $run.anchor_hash
    }
  }
  if ($run.rationale_file | is-not-empty) {
    print $"(ansi blue)Preparing rationale anchor from ($run.rationale_file)...(ansi reset)"
    let out = (^$"($env.FILE_PWD)/rationale.nu" prepare $run.env --project-id $run.blockfrost_project_id --file $run.rationale_file --cli $run.cli | from json)
    print $"  anchor: (ansi green)($out.anchorUrl)(ansi reset)"
    return {
      url: $out.anchorUrl
      hash: $out.hash
    }
  }
  {url: "", hash: ""}
}
# Build + sign one orchestrator-multisig CC vote tx. Faithful port of
# vote-with-cc.sh, parameterized by the member dir + decision + resolved anchor.
# `anchor_hash` may be "" (then it is computed from the anchor URL via gateway).
# Returns the path to the signed tx, or null on dry-run.
def assemble-orch-cc [
  run: record
  member: record
  anchor: string
  anchor_hash: string
]: nothing -> any {
  let cli = $run.cli
  let cc = $member.name
  let decision = $member.decision
  let orch_dir = $"secrets/envs/($run.env)/cc-keys/($cc)"
  let inithot = $"($orch_dir)/init-hot"
  let signer = $"($orch_dir)/roles"
  let orch_addr = (secret-str $"($orch_dir)/orchestrator.addr")
  print $"\n(ansi blue)Assembling orchestrator-CC tx for ($cc) \(decision: ($decision)\)(ansi reset)"
  # Report the orchestrator payment address balance. This address pays the fee
  # for every vote of this member and must be refilled before it runs dry.
  let orch_utxos = (^$cli latest query utxo --address $orch_addr --testnet-magic $run.magic --output-json | from json)
  let orch_lovelace = ($orch_utxos | values | reduce --fold 0 {|u, acc| $acc + ($u.value.lovelace? | default 0) })
  let orch_ada = ($orch_lovelace / 1000000 | math round --precision 3)
  let warn_lovelace = ($run.orch_warn_ada * 1000000)
  print $"  Orchestrator (ansi cyan)($cc)(ansi reset) payment address: ($orch_addr)"
  print $"    balance: (ansi green)($orch_ada) ADA(ansi reset) across ($orch_utxos | columns | length) UTxO\(s\) \(($orch_lovelace) lovelace\)"
  if $orch_lovelace < $warn_lovelace {
    print $"    (ansi red_bold)⚠ LOW BALANCE(ansi reset)(ansi red) — below ($run.orch_warn_ada) ADA; refill this orchestrator address soon.(ansi reset)"
  }
  if $run.dry_run {
    print $"(ansi yellow)[dry-run] would build orchestrator-CC vote tx for ($cc) with anchor ($anchor).(ansi reset)"
    return null
  }
  if ($anchor | is-empty) {
    error make --unspanned {
      msg: $"Orchestrator CC vote for ($cc) needs a rationale anchor. Pass --anchor-url, or --rationale-file (with --blockfrost-project-id / $env.BLOCKFROST_IPFS_PROJECT_ID)."
    }
  }
  let workdir = ($run.tmp | path join $"orch-($cc)")
  mkdir $workdir
  # Anchor hash: use the precomputed (local) hash if provided, else hash the
  # content fetched from the anchor URL via the gateway (IPFS_GATEWAY_URI is set
  # for the whole run in `main`, defaulting to ipfs.io).
  let anchor_hash = (if ($anchor_hash | is-not-empty) {
    $anchor_hash
  } else {
    ^$cli hash anchor-data --url $anchor | into string | str trim
  })
  # Locate the hot NFT UTxO (single token of the member's minting policy).
  let nft_addr = (secret-str $"($inithot)/nft.addr")
  let policy = (secret-str $"($inithot)/minting.plutus.hash")
  let token = (secret-str $"($inithot)/nft-token-name")
  let nft_utxo_file = ($workdir | path join "hot-nft.utxo")
  let utxos = (^$cli latest query utxo --address $nft_addr --testnet-magic $run.magic --output-json | from json)
  let nft_entries = ($utxos | transpose k v | where {|r| ($r.v.value | get -o $policy | get -o $token | is-not-empty) })
  if ($nft_entries | is-empty) {
    error make --unspanned {
      msg: $"No hot-NFT UTxO found at ($nft_addr) for member ($cc)."
    }
  }
  let nft_utxo = ($nft_entries | reduce --fold {} {|it, acc| $acc | insert $it.k $it.v })
  $nft_utxo | to json | save --raw --force $nft_utxo_file
  let nft_txin = ($nft_utxo | columns | first)
  # orchestrator-cli builds the vote redeemer/datum/value into a vote dir.
  let votedir = ($workdir | path join "vote")
  (^orchestrator-cli vote --utxo-file $nft_utxo_file --hot-credential-script-file (secret-file $run $"($inithot)/credential.plutus") --governance-action-tx-id $run.action_id --governance-action-index $run.action_idx (decision-flag $decision) --metadata-url $anchor --metadata-hash $anchor_hash --out-dir $votedir)
  # Orchestrator funds + collateral come from its own address' first UTxO
  # (reusing the balance query above).
  let orch_txin = ($orch_utxos | columns | get -o 0)
  if ($orch_txin | is-empty) {
    error make --unspanned {
      msg: $"No UTxO at orchestrator address for member ($cc)."
    }
  }
  let body = ($workdir | path join "body.json")
  (^$cli latest transaction build --tx-in $orch_txin --tx-in-collateral $orch_txin --tx-in $nft_txin --tx-in-script-file (secret-file $run $"($inithot)/nft.plutus") --tx-in-inline-datum-present --tx-in-redeemer-file ($votedir | path join "redeemer.json") --tx-out (open --raw ($votedir | path join "value") | into string | str trim) --tx-out-inline-datum-file ($votedir | path join "datum.json") --required-signer-hash (^orchestrator-cli extract-pub-key-hash (secret-file $run $"($signer)/voter-1.crt")) --required-signer-hash (^orchestrator-cli extract-pub-key-hash (secret-file $run $"($signer)/voter-2.crt")) --required-signer-hash (^orchestrator-cli extract-pub-key-hash (secret-file $run $"($signer)/voter-3.crt")) --vote-file ($votedir | path join "vote") --vote-script-file (secret-file $run $"($inithot)/credential.plutus") --vote-redeemer-value "{}" --change-address $orch_addr --testnet-magic $run.magic --out-file $body)
  # Witness with the 3 voters + orchestrator, then assemble.
  let witnesses = (["voter-1", "voter-2", "voter-3"] | each {|v|
    let w = ($workdir | path join $"($v).witness")
    (^$cli latest transaction witness
      --tx-body-file $body
      --signing-key-file (secret-file $run $"($signer)/($v).skey")
      --testnet-magic $run.magic
      --out-file $w)
    $w
  })
  let orch_witness = ($workdir | path join "orchestrator.witness")
  (^$cli latest transaction witness --tx-body-file $body --signing-key-file (secret-file $run $"($orch_dir)/orchestrator.skey") --testnet-magic $run.magic --out-file $orch_witness)
  let signed = ($workdir | path join "vote-tx.signed")
  let wit_args = (
    [$witnesses, $orch_witness] | flatten | each {|w| [--witness-file $w] } | flatten
  )
  (^$cli latest transaction assemble --tx-body-file $body ...$wit_args --out-file $signed)
  $signed
}
# Remove the temp dir holding decrypted secrets + tx artifacts.
def cleanup [run: record]: nothing -> nothing {
  if ($run.tmp? | is-not-empty) and ($run.tmp | path exists) {
    rm --recursive --force --permanent $run.tmp
  }
}
# ─── entrypoint ────────────────────────────────────────────────────────────────
# Interactively assemble and submit governance votes for an environment.
def main [
  node_env: string            # Node environment (e.g. preprod, preview, leios, dijkstra)
  action_id: string           # Governance action tx id
  action_idx: int             # Governance action index
  --decision: string = "yes"  # Default decision offered per voter: yes|no|abstain
  --anchor-url: string = ""   # CC rationale anchor (required for orchestrator-CC votes)
  --anchor-hash: string = ""  # Precomputed anchor-data hash; if omitted, fetched from --anchor-url via $env.IPFS_GATEWAY_URI (default https://ipfs.io)
  --rationale-file: path = "" # Sign + upload this rationale doc to IPFS, use as anchor (orchestrator-CC; alt to --anchor-url)
  --blockfrost-project-id: string = "" # Blockfrost IPFS project id for --rationale-file uploads; defaults to $env.BLOCKFROST_IPFS_PROJECT_ID
  --cli: string = ""          # Override the cardano-cli binary (default: auto)
  --orch-warn-ada: int = 10   # Warn when an orchestrator-CC payment address balance is below this many ADA
  --include-inactive-cc       # Offer CC members even if their hot credential is not currently active on-chain
  --submit                    # Submit the assembled tx(s) (still prompts unless --yes); default is build+sign only
  --yes                       # Auto-confirm submit prompts (only meaningful with --submit)
  --dry-run                   # Discover, prompt and report the plan; build nothing
]: nothing -> nothing {
  let allowed_envs = (env-magic | columns)
  if $node_env not-in $allowed_envs {
    error make --unspanned {
      msg: $"Unsupported env '($node_env)'. One of: ($allowed_envs | str join ', ')"
    }
  }
  if $decision not-in [yes, no, abstain] {
    error make --unspanned {
      msg: $"--decision must be yes, no or abstain \(got '($decision)'\)"
    }
  }
  # Default the IPFS gateway for the whole run so cardano-cli can resolve ipfs://
  # anchors — both the anchor-hash computation and `transaction build`, which
  # re-validates the anchor — without requiring IPFS_GATEWAY_URI; respect it when set.
  $env.IPFS_GATEWAY_URI = ($env.IPFS_GATEWAY_URI? | default "https://ipfs.io")
  let expected_magic = (env-magic | get $node_env)
  let magic = (require-node-env $node_env $expected_magic)
  let run = {
    env: $node_env
    action_id: $action_id
    action_idx: $action_idx
    decision: $decision
    anchor_url: $anchor_url
    anchor_hash: $anchor_hash
    rationale_file: $rationale_file
    blockfrost_project_id: (if ($blockfrost_project_id | is-empty) {
      $env.BLOCKFROST_IPFS_PROJECT_ID? | default ""
    } else { $blockfrost_project_id })
    cli: (select-cli $node_env $cli)
    orch_warn_ada: $orch_warn_ada
    include_inactive_cc: $include_inactive_cc
    magic: $magic
    submit: $submit
    yes: $yes
    dry_run: $dry_run
    tmp: (mktemp --directory)
  }
  chmod 0700 $run.tmp
  try {
    print $"(ansi attr_bold)Voting tool(ansi reset) — env ($run.env), cli ($run.cli), action ($run.action_id)#($run.action_idx)"
    require-synced $run
    let action = (gov-action-state $run)
    if ($action | is-empty) {
      error make --unspanned {
        msg: $"Action ($run.action_id)#($run.action_idx) not found in ($run.env) gov-state proposals \(expired or wrong id?\)."
      }
    }
    print "\nCurrent gov-action state:"
    print ($action | to yaml)
    let cc_mode = (detect-cc-mode $run.env)
    let ccs = (filter-active-cc $run $cc_mode (discover-cc $run.env $cc_mode))
    let dreps = (discover-dreps $run.env)
    let pools = (discover-pools $run.env)
    let sel = (collect-selections $run $cc_mode $ccs $dreps $pools)
    let total = (($sel.simple_cc | length) + ($sel.orch_cc | length) + ($sel.drep | length) + ($sel.pool | length))
    if $total == 0 {
      print $"\n(ansi yellow)No voters selected. Nothing to do.(ansi reset)"
      cleanup $run
      return
    }
    print $"\n(ansi green_bold)Selected ($total) vote\(s\).(ansi reset)"
    # 1) One combined tx for everything combinable.
    let combined = (assemble-combined $run $sel)
    if ($combined | is-not-empty) {
      review-and-submit $run "combined vote tx (simple-CC + DRep + pools)" $combined
    }
    # 2) One tx per orchestrator-CC member, sharing one rationale anchor that is
    #    resolved (signed + uploaded) at most once.
    if ($sel.orch_cc | is-not-empty) {
      let anchor = (resolve-orch-anchor $run)
      for m in $sel.orch_cc {
        let signed = (assemble-orch-cc $run $m $anchor.url $anchor.hash)
        if ($signed | is-not-empty) {
          review-and-submit $run $"orchestrator-CC vote: ($m.name)" $signed
        }
      }
    }
    print $"\n(ansi green)Done.(ansi reset)"
  } catch {|err|
    # Clean up, then re-raise the original error intact ($err.raw preserves the
    # span) so the failing line/location is visible instead of a bare message.
    cleanup $run
    error make $err.raw
  }
  cleanup $run
}
