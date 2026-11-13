#!/usr/bin/env nu
# Offline workflow tests: no node, real secrets, network, or transactions.
# Run from any directory: nu --no-config-file scripts/gov/tests/test-submit-action.nu
use std/assert
const script = path self ../submit-action.nu
const mock = path self mock-command.nu
def shell-quote [value: string] { "'" + ($value | str replace --all "'" "'\"'\"'") + "'" }
def calls [] {
  if ("calls.jsonl" | path exists) {
    open --raw calls.jsonl | lines | each { from json }
  } else { [] }
}
def flag-value [args: list<string>, flag: string] {
  $args | get ((
    $args | enumerate | where item == $flag | first | get index
  ) + 1)
}
def run-tool [
  extra: list<string> = []
  --action: string = pparams
  --network: string = leios
  --parent: string = none
  --omit-parent
  --fails
  --prompt-error
] {
  let args = [
    $script
    $network
    $action
    --anchor-url
    ipfs://mock
    --payment-key
    payer
    --stake-key
    stake
    --guardrails-file
    guard.plutus
    --out-dir
    result
  ] | append (if $omit_parent { [] } else { [--previous-action, $parent] }) | append $extra
  let invocation = if $prompt_error {
    # A terminal-backed `input` may ignore piped EOF. Simulate the read error
    # without depending on the caller's terminal or Nushell input behavior.
    let code = 'def input [prompt: string] { error make {msg: "mock confirmation input unavailable"} }; source ' + ($script | to json --raw) + '; main ' + ($args | skip 1 | each {|arg| if $arg starts-with '--' { $arg } else { $arg | to nuon --raw } } | str join ' ')
    [-c, $code]
  } else { $args }
  let result = "" | ^timeout 30s $nu.current-exe --no-config-file ...$invocation | complete
  assert ($result.exit_code not-in [124, 137]) "Test command timed out or was killed; this is not an expected workflow failure"
  assert equal ($result.exit_code == 0) (not $fails) ($result.stdout + $result.stderr)
  assert equal (glob private-tmp/*) [] "Temporary decrypted keys were not cleaned up"
  $result
}
def hint [action: string, state: record, --reply: string] {
  $state | to json | save --force gov-state.json
  # Replace only the interactive prompt; exercise real lookup and validation.
  let code = 'def input [prompt: string] { ' + ($reply | default "" | to json --raw) + ' }; source ' + ($script | to json --raw) + '; previous-args {action: ' + ($action | to json --raw) + ', cli: "cardano-cli", era: "dijkstra", net: [--testnet-magic "164"]} "" | to json --raw | print'
  ^timeout 30s $nu.current-exe --no-config-file -c $code | complete
}
def hint-args [result: record] {
  assert equal $result.exit_code 0 $result.stderr
  $result.stdout | lines | last | from json
}
def state-for [ids: record] { {
  nextRatifyState: {
    nextEnactState: {prevGovActionIds: $ids}
  }
  proposals: []
} }
def test-dry-run [] {
  run-tool [--dry-run, --max-endorser-block-txs-size, "2000000"] | ignore
  assert (not ("result" | path exists))
  assert (calls | all {|c| $c.0 != "just" and "build" not-in $c and "sign" not-in $c and "submit" not-in $c })
}
def test-default-build [] {
  run-tool [--max-endorser-block-txs-size, "2000000", --max-endorser-block-references-size, "308000"] | ignore
  let create = calls | where {|c| "create-protocol-parameters-update" in $c and "--out-file" in $c } | first
  assert equal (flag-value $create "--max-endorser-block-txs-size") "2000000"
  assert equal (flag-value $create "--max-endorser-block-references-size") "308000"
  assert ("--constitution-script-hash" in $create)
  let build = calls | where {|c| "transaction" in $c and "build" in $c } | first
  assert ((flag-value $build "--tx-in") != (flag-value $build "--tx-in-collateral"))
  assert (calls | all {|c| "submit" not-in $c })
  assert ("result/transaction.txsigned" | path exists)
  assert (open --raw result/README.md | str contains "not submitted")
}
def test-explicit-submission [] {
  run-tool [--submit, --yes, --max-tx-size, "18000"] | ignore
  assert equal (calls | where {|c| "submit" in $c } | length) 1
  assert (open --raw result/README.md | str contains "confirmation pending")
}
def test-missing-confirmation [] {
  let result = run-tool [--submit, --max-tx-size, "18000"] --fails --prompt-error
  assert ($result.stderr | str contains "mock confirmation input unavailable") ($result.stdout + $result.stderr)
  assert (calls | all {|c| "submit" not-in $c })
  assert ("result/transaction.txsigned" | path exists)
}
def test-mainnet [] {
  $env.TESTNET_MAGIC = "764824073"
  run-tool --action info --network mainnet --omit-parent | ignore
  assert (calls | all {|c| "--testnet" not-in $c and "--testnet-magic" not-in $c })
}
def test-wrong-network [] {
  $env.TESTNET_MAGIC = "2"
  run-tool --fails | ignore
  assert equal (calls) []
}
def test-bad-anchor [] {
  run-tool [
    --anchor-hash
    ("0" | fill -w 64 -c 0)
  ] --fails | ignore
  assert (calls | all {|c| $c.0 != "just" })
}
def test-build-failure [] {
  $env.MOCK_BUILD_FAIL = "1"
  run-tool [--submit, --yes] --fails | ignore
  assert (calls | all {|c| "sign" not-in $c and "submit" not-in $c })
}
def test-insufficient-funds [] {
  $env.MOCK_BALANCE = "100000000000"
  run-tool --fails | ignore
  assert (calls | all {|c| "sign" not-in $c })
}
def test-previous-action [] {
  $env.MOCK_NO_SCRIPT = "1"
  run-tool --parent (("b" | fill -w 64 -c b) + "#2") | ignore
  let create = calls | where {|c| "create-protocol-parameters-update" in $c and "--out-file" in $c } | first
  assert equal (flag-value $create "--prev-governance-action-index") "2"
  assert ("--constitution-script-hash" not-in $create)
}
def test-reserved-flags [] {
  run-tool [--out-file=/tmp/override] --fails | ignore
  assert equal (calls) []
}
def test-hint-purposes [] {
  let ids = [PParamUpdate, HardFork, Constitution, Committee] | enumerate | reduce --fold {} {|it, acc|
    $acc | insert $it.item {txId: (($it.index + 1 | into string) | fill -w 64 -c ($it.index + 1 | into string)), govActionIx: $it.index}
  }
  for case in [[action, purpose]; [create-protocol-parameters-update, PParamUpdate], [create-hardfork, HardFork], [create-constitution, Constitution], [update-committee, Committee], [create-no-confidence, Committee]] {
    let args = hint $case.action (state-for $ids) | hint-args $in
    let expected = $ids | get $case.purpose
    assert equal $args.1 $expected.txId
    assert equal $args.3 ($expected.govActionIx | into string)
  }
}
def test-null-and-missing-hint [] {
  assert equal (hint create-protocol-parameters-update (state-for {PParamUpdate: null}) | hint-args $in) []
  let result = hint create-protocol-parameters-update {}
  assert ($result.exit_code != 0)
  assert ($result.stderr | str contains "Could not look up a predecessor hint")
}
def test-projected-hint [] {
  let parent = {
    txId: ("c" | fill -w 64 -c c)
    govActionIx: 0
  }
  let state = state-for {PParamUpdate: $parent} | update proposals [
    {actionId: $parent}
  ]
  let replacement = "d" | fill -w 64 -c d
  let result = hint create-protocol-parameters-update $state --reply ($replacement + "#3")
  let args = hint-args $result
  assert ($result.stdout | str contains "not confirmed enactment")
  assert equal $args.1 $replacement
  assert equal $args.3 "3"
}
def run-case [test: record] {
  let root = mktemp -d -t submit-action-test.XXXXXXXX
  let result = try {
    do {
      cd $root
      mkdir bin private-tmp
      for name in [cardano-cli, curl, just] {
        let wrapper = '#!/bin/sh' + "\nexec " + (shell-quote $nu.current-exe) + ' --no-config-file ' + (shell-quote $mock) + ' ' + $name + ' "$@"' + "\n"
        $wrapper | save ($root | path join bin $name)
        ^chmod 755 ($root | path join bin $name)
      }
      for name in [payer.vkey, payer.skey, stake.vkey] {
        {
          sops: {}
          data: mock
        } | to json | save $name
      }
      {
        body: {
          title: Test
          abstract: Test
          motivation: Test
          rationale: Test
        }
      } | to json | save rationale.json
      "{}" | save guard.plutus
      $env.TESTNET_MAGIC = "164"
      $env.CARDANO_NODE_SOCKET_PATH = "/mock.socket"
      $env.TMPDIR = $root | path join private-tmp
      $env.PATH = $env.PATH | prepend ($root | path join bin)
      $env.MOCK_SYNC = "100.00"
      $env.MOCK_NO_SCRIPT = ""
      $env.MOCK_BUILD_FAIL = ""
      $env.MOCK_BALANCE = "200000000000"
      do $test.run
    }
    {ok: true, message: ""}
  } catch {|err| {
    ok: false
    message: $err.msg
  } }
  rm --recursive $root
  if $result.ok { print $"PASS ($test.name)" } else { print $"FAIL ($test.name): ($result.message)" }
  $result.ok
}
def main []: nothing -> nothing {
  let tests = [
    {
      name: dry-run
      run: { test-dry-run }
    }
    {
      name: default-build
      run: { test-default-build }
    }
    {
      name: explicit-submission
      run: { test-explicit-submission }
    }
    {
      name: missing-confirmation
      run: { test-missing-confirmation }
    }
    {
      name: mainnet
      run: { test-mainnet }
    }
    {
      name: wrong-network
      run: { test-wrong-network }
    }
    {
      name: bad-anchor
      run: { test-bad-anchor }
    }
    {
      name: build-failure
      run: { test-build-failure }
    }
    {
      name: insufficient-funds
      run: { test-insufficient-funds }
    }
    {
      name: previous-action
      run: { test-previous-action }
    }
    {
      name: reserved-flags
      run: { test-reserved-flags }
    }
    {
      name: hint-purposes
      run: { test-hint-purposes }
    }
    {
      name: null-and-missing-hint
      run: { test-null-and-missing-hint }
    }
    {
      name: projected-hint
      run: { test-projected-hint }
    }
  ]
  let results = $tests | each {|test| run-case $test }
  let passed = $results | where $it | length
  print $"($passed)/($tests | length) tests passed"
  if $passed != ($tests | length) { exit 1 }
}
