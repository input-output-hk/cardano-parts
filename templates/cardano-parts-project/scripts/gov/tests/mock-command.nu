#!/usr/bin/env nu
# Offline command stand-ins: never contact a node or decrypt real keys.
def --wrapped main [name: string, ...args: string] {
  ([$name] | append $args | to json --raw) + "\n" | save --append calls.jsonl
  let value = {|flag|
    $args | get ((
      $args | enumerate | where item == $flag | first | get index
    ) + 1)
  }
  let emit = {|data|
    $data | to json --raw | print
  }
  if $name == "curl" {
    open --raw rationale.json | save --force (do $value "--output")
  } else if $name == "just" {
    do $emit {type: PaymentSigningKeyShelley_ed25519, cborHex: "00"}
  } else if "hash" in $args and "anchor-data" in $args {
    # Deterministic stand-in; tests exercise hash comparison, not CLI hashing.
    open --raw (do $value "--file-binary") | hash sha256 | print
  } else if "--help" in $args {
    print "mock help"
  } else if "query" in $args {
    match (do $value query) {
      tip => {
        do $emit {
          era: Dijkstra
          epoch: 7
          syncProgress: ($env.MOCK_SYNC? | default "100.00")
        }
      }
      protocol-parameters => { do $emit {govActionDeposit: 100000000000, maxEndorserBlockTxsSize: 260000, maxEndorserBlockReferencesSize: 40000} }
      constitution => {
        do $emit {
          script: (if ($env.MOCK_NO_SCRIPT? | default "") == "1" { null } else { "abcd" })
        }
      }
      gov-state => {
        open gov-state.json | do $emit $in
      }
      utxo => {
        do $emit {
          "a#0": {
            value: {
              lovelace: ($env.MOCK_BALANCE? | default "200000000000" | into int)
            }
          }
          "b#0": {
            value: {lovelace: 10000000}
          }
        }
      }
      _ => {
        error make {
          msg: $"Unexpected query: ($args)"
        }
      }
    }
  } else if "policyid" in $args {
    print abcd
  } else if "address" in $args {
    print addr_test_mock
  } else if "txid" in $args {
    do $emit {
      txhash: ("a" | fill -w 64 -c a)
    }
  } else if "submit" in $args {
    print accepted
  } else if "view" in $args {
    if "transaction" in $args and ($args | first 3) != [debug, transaction, view] {
      error make {msg: "Invalid argument `view'"}
    }
    do $emit {review: true}
  } else if "--out-file" in $args {
    if ($env.MOCK_BUILD_FAIL? | default "") == "1" and "build" in $args {
      error make {msg: "guardrails validation failed"}
    }
    "{}" | save --force (do $value "--out-file")
  } else {
    error make {
      msg: $"Unexpected command: ($args)"
    }
  }
}
