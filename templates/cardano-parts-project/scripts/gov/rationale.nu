#!/usr/bin/env nu
# CC voting-rationale anchor helper
#
# Automates the tedious CC rationale anchor process: sign a CIP-100/136
# rationale document, upload it to IPFS via Blockfrost, and emit the
# `ipfs://<CID>` anchor URL plus the locally-computed anchor-data hash — exactly
# what the voting flow needs.
#
# The rationale doc itself (a CIP-136 JSON-LD file, by default ./rationale.json)
# is consumed AS-IS — edit its body (summary/rationaleStatement/...) beforehand.
# A signed sibling `<file>.signed` is produced and uploaded.
#
# SUBCOMMANDS:
#   rationale.nu sign <env> [--file rationale.json] [--cli cardano-cli]
#       Sign the rationale with the env's rationale-signer key (cardano-signer
#       --cip100), verify it, and write <file>.signed.
#
#   rationale.nu upload --file <file.signed> [--project-id <id>] [--no-pin]
#       Upload an (already signed) file to IPFS via Blockfrost; prints `ipfs://<CID>`.
#
#   rationale.nu prepare <env> [--project-id <id>] [--file rationale.json]
#                        [--cli cardano-cli] [--verify]
#       Full chain: sign -> upload -> hash. Emits a JSON record on stdout:
#         {"anchorUrl": "ipfs://...", "signedFile": "...", "hash": "..."}
#       (all human progress goes to stderr). This is what `vote.nu
#       --rationale-file` consumes.
#
# IPFS UPLOAD (Blockfrost): uploads go to the Blockfrost IPFS API
# (https://ipfs.blockfrost.io/api/v0 by default; override with
# $env.BLOCKFROST_IPFS_URL). Authenticate with a Blockfrost IPFS project id via
# --project-id or $env.BLOCKFROST_IPFS_PROJECT_ID — supply it at runtime (your
# shell / own secret store); it is NOT stored in this repo. The token is passed
# to curl through a stdin config (-K -) so it never appears in the process list.
# Blockfrost garbage-collects unpinned files, so uploads are pinned by default.
#
# DEPLOYMENT CONFIG (optional): $env.CC_RATIONALE_AUTHOR sets the CIP-100 author
# name (default "CC member"), e.g. exported from custom.just.
#
# DEPENDENCIES: just (sops-decrypt-binary), cardano-signer, cardano-cli, curl.
# Blockfrost IPFS API base URL; override for a self-hosted Blockfrost gateway.
def blockfrost-ipfs-url []: nothing -> string {
  $env.BLOCKFROST_IPFS_URL? | default "https://ipfs.blockfrost.io/api/v0" | str trim | str trim --right --char '/'
}
# Resolve the Blockfrost IPFS project id from the flag or the environment.
def blockfrost-project-id [flag: string]: nothing -> string {
  let id = (if ($flag | is-empty) {
    $env.BLOCKFROST_IPFS_PROJECT_ID? | default ""
  } else { $flag } | str trim)
  if ($id | is-empty) {
    error make --unspanned {msg: "Blockfrost IPFS project id required: pass --project-id or set $env.BLOCKFROST_IPFS_PROJECT_ID"}
  }
  $id
}
# Decrypt a sops-encrypted secret and return its trimmed contents as a string.
def secret-str [rel: string] {
  ^just sops-decrypt-binary $rel | into string | str trim
}
def main [] {
  print "CC rationale anchor helper. Subcommands: sign | upload | prepare."
  print "Run `rationale.nu <subcommand> --help` for details."
}
# Sign a rationale doc with the env's rationale-signer key; returns the signed
# file path.
def 'main sign' [
  node_env: string            # Node environment (preprod, preview, ...)
  --file: path = "rationale.json"  # Rationale doc to sign
  --cli: string = "cardano-cli"    # cardano-cli binary (unused here; kept for symmetry)
] {
  if not ($file | path exists) {
    error make --unspanned {
      msg: $"Rationale file not found: ($file)"
    }
  }
  let signed = $"($file).signed"
  let tmp = (mktemp --directory)
  chmod 0700 $tmp
  try {
    # cardano-signer wants the raw skey in a file; rationale-signer.json holds it
    # under .output.skey (same extraction sign-cc-rationale.sh does).
    let skey_file = ($tmp | path join "rationale-signer.skey")
    # .output.skey may be a bech32 string OR a key-file object ({type,cborHex}).
    # Mirror `jq -r`: write strings raw, objects as JSON, so cardano-signer
    # --secret-key gets the right bytes either way.
    let skey = (secret-str $"secrets/envs/($node_env)/cc-keys/rationale-signer.json" | from json | get output.skey)
    (if ($skey | describe | str starts-with "string") { $skey } else {
      $skey | to json
    }) | save --raw --force $skey_file
    chmod 0600 $skey_file
    print -e $"Signing ($file) for env ($node_env)..."
    # CIP-100 author name. Treat unset OR blank CC_RATIONALE_AUTHOR the same
    # (nu's `default` only fills null, not ""), so a blank never yields a
    # dangling " for <Env>".
    let author = ($env.CC_RATIONALE_AUTHOR? | default "" | str trim)
    let author = (if ($author | is-empty) { "CC member" } else { $author })
    # `| ignore` keeps cardano-signer's stdout from polluting `prepare`'s JSON
    # output; the signed doc is written to --out-file regardless.
    (^cardano-signer sign --cip100 --data-file $file --secret-key $skey_file --author-name $"($author) for ($node_env | str capitalize)" --replace --out-file $signed) | ignore
    # Verify the produced witness before trusting it.
    ^cardano-signer verify --cip100 --data-file $signed --json | from json | ignore
    print -e $"Signed + verified -> ($signed)"
  } catch {|err|
    rm --recursive --force --permanent $tmp
    error make --unspanned {
      msg: $err.msg
    }
  }
  rm --recursive --force --permanent $tmp
  $signed
}
# Upload a file to the IPFS node and print `ipfs://<CID>` on stdout.
def 'main upload' [
  --file: path                     # File to upload (typically <rationale>.signed)
  --project-id: string = ""        # Blockfrost IPFS project id; defaults to $env.BLOCKFROST_IPFS_PROJECT_ID
  --no-pin                         # Do not pin after upload (Blockfrost GCs unpinned files)
] {
  let cid = (upload-file $file (blockfrost-project-id $project_id) (not $no_pin))
  print $"ipfs://($cid)"
}
# Full chain: sign -> upload -> hash. Emits a JSON record on stdout; progress to
# stderr. Consumed by vote.nu --rationale-file.
def 'main prepare' [
  node_env: string                 # Node environment
  --project-id: string = ""        # Blockfrost IPFS project id; defaults to $env.BLOCKFROST_IPFS_PROJECT_ID
  --file: path = "rationale.json"  # Rationale doc to sign + upload
  --cli: string = "cardano-cli"    # cardano-cli binary used for hashing
  --verify                         # After upload, fetch via $env.IPFS_GATEWAY_URI (default https://ipfs.io) and confirm the hash matches
] {
  let project_id = (blockfrost-project-id $project_id)
  let signed = (main sign $node_env --file $file --cli $cli)
  let cid = (upload-file $signed $project_id true)
  let url = $"ipfs://($cid)"
  # Hash the exact local bytes we uploaded — deterministic, no gateway round-trip.
  let hash = (^$cli hash anchor-data --file-binary $signed | into string | str trim)
  print -e $"Anchor: (ansi green)($url)(ansi reset)  hash: ($hash)"
  if $verify {
    print -e "Verifying the anchor is fetchable and its hash matches..."
    let fetched = (with-env {IPFS_GATEWAY_URI: ($env.IPFS_GATEWAY_URI? | default "https://ipfs.io")} {
      try { ^$cli hash anchor-data --url $url | into string | str trim } catch { "" }
    })
    if ($fetched | is-empty) {
      print -e $"(ansi yellow)Warning: could not fetch ($url) via ipfs.io yet \(propagation lag is normal\). Local hash stands.(ansi reset)"
    } else if $fetched != $hash {
      error make --unspanned {
        msg: $"Anchor hash mismatch: local ($hash) != fetched ($fetched). Do not vote with this anchor."
      }
    } else {
      print -e $"(ansi green)Verified: gateway hash matches.(ansi reset)"
    }
  }
  {
    anchorUrl: $url
    signedFile: $signed
    hash: $hash
  } | to json
}
# ─── internals ────────────────────────────────────────────────────────────────
# Add a file to IPFS via Blockfrost and return the CID. Blockfrost garbage-
# collects unpinned files, so pin immediately after upload unless pin=false. The
# project id is fed to curl through a stdin config (-K -) so it never hits the
# process list.
def upload-file [file: path, project_id: string, pin: bool] {
  if not ($file | path exists) {
    error make --unspanned {
      msg: $"Upload file not found: ($file)"
    }
  }
  let base = (blockfrost-ipfs-url)
  let hdr = $"header = \"project_id: ($project_id)\"\n"
  print -e $"Uploading ($file) to Blockfrost IPFS \(($base)\)..."
  let resp = ($hdr | ^curl -sS --fail-with-body -K - -X POST -F $"file=@($file)" $"($base)/ipfs/add")
  # Blockfrost's add returns a CIDv0 (Qm...) — there is no cid-version option, and
  # v0 is what we want (shortest ipfs:// anchor to fit the Cardano anchor-URL field).
  let cid = ($resp | from json | get ipfs_hash?)
  if ($cid | is-empty) {
    error make --unspanned {
      msg: $"Blockfrost IPFS add did not return an ipfs_hash. Response: ($resp)"
    }
  }
  if $pin {
    print -e $"Pinning ($cid)..."
    let pin_resp = ($hdr | ^curl -sS --fail-with-body -K - -X POST $"($base)/ipfs/pin/add/($cid)")
    let state = ($pin_resp | from json | get state?)
    if ($state | is-empty) {
      print -e $"(ansi yellow)Warning: pin request returned no state. Response: ($pin_resp)(ansi reset)"
    } else {
      print -e $"Pin state: ($state)"
    }
  }
  $cid
}
