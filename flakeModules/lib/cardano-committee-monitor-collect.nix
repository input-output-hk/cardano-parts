# Shared collector script. callPackage'd from both the production unit
# (profile-cardano-committee-monitor.nix) and the fixture check; the
# `cardano-cli` parameter lets the check swap in a fixture-driven shim.
{
  pkgs,
  cardano-cli ? pkgs.cardano-cli,
}:
pkgs.writeShellApplication {
  name = "cardano-committee-monitor-collect";
  runtimeInputs = [cardano-cli pkgs.jq pkgs.coreutils];
  text = ''
    set -euo pipefail
    : "''${OUT:?OUT (output .prom path) must be set}"
    : "''${ENVIRONMENT_NAME:?ENVIRONMENT_NAME must be set}"
    : "''${SECONDS_PER_EPOCH:?SECONDS_PER_EPOCH must be set}"
    TMP="$OUT.tmp"

    # `query committee-state` returns the top-level `epoch` it was
    # computed against, so a second `query tip` RPC would only open an
    # epoch-boundary race window.
    CS=$(cardano-cli latest query committee-state)

    # `environment` is baked in here because alloy's node-exporter
    # relabel chain sets only `instance` and `job` for textfile-collector
    # samples — there is no scraper-side label source. The same chain
    # means `node_textfile_mtime_seconds` does NOT carry `environment`,
    # which is why `cardano_cc_metrics_stale` keys on `instance` only.
    #
    # The `.epoch == null` guard aborts before `mv "$TMP" "$OUT"`, so the
    # previous .prom stays in place and staleness surfaces as
    # cardano_cc_metrics_stale rather than as zero values.
    jq -r --arg     env "$ENVIRONMENT_NAME" \
          --argjson spe "$SECONDS_PER_EPOCH" '
      def lbl: "environment=\"\($env)\",cold_credential=\"\(.key)\"";
      if .epoch == null then error("cardano-cli returned no .epoch") else . end
      | .epoch as $epoch
      | .committee
      | to_entries as $members
      | (
          "# HELP cardano_cc_member_epochs_until_expiration Epochs remaining before this committee member term expires.",
          "# TYPE cardano_cc_member_epochs_until_expiration gauge",
          # Expiration is null for newly-enacted members; their term
          # metrics are intentionally absent — alert via
          # cardano_cc_member_state{state=...} instead.
          ($members[]
            | (.value.expiration // null) as $exp
            | select($exp != null)
            | "cardano_cc_member_epochs_until_expiration{\(lbl)} \($exp - $epoch)"),

          "# HELP cardano_cc_member_seconds_until_expiration Seconds remaining before this committee member term expires (epochs delta times cardano_cc_seconds_per_epoch).",
          "# TYPE cardano_cc_member_seconds_until_expiration gauge",
          ($members[]
            | (.value.expiration // null) as $exp
            | select($exp != null)
            | "cardano_cc_member_seconds_until_expiration{\(lbl)} \(($exp - $epoch) * $spe)"),

          "# HELP cardano_cc_member_hot_cred_status Info gauge (value 1) carrying the current hotCredsAuthStatus.tag in the status label.",
          "# TYPE cardano_cc_member_hot_cred_status gauge",
          ($members[]
            | "cardano_cc_member_hot_cred_status{\(lbl),status=\"\(.value.hotCredsAuthStatus.tag)\"} 1"),

          "# HELP cardano_cc_member_state Info gauge (value 1) carrying the current committee-member status in the state label.",
          "# TYPE cardano_cc_member_state gauge",
          ($members[]
            | "cardano_cc_member_state{\(lbl),state=\"\(.value.status)\"} 1"),

          "# HELP cardano_cc_member_next_epoch_change Info gauge (value 1) carrying nextEpochChange in the change label.",
          "# TYPE cardano_cc_member_next_epoch_change gauge",
          ($members[]
            | "cardano_cc_member_next_epoch_change{\(lbl),change=\"\(.value.nextEpochChange.tag)\"} 1"),

          "# HELP cardano_cc_current_epoch Current epoch on this environment.",
          "# TYPE cardano_cc_current_epoch gauge",
          "cardano_cc_current_epoch{environment=\"\($env)\"} \($epoch)",

          "# HELP cardano_cc_member_count Total committee members on this environment.",
          "# TYPE cardano_cc_member_count gauge",
          "cardano_cc_member_count{environment=\"\($env)\"} \($members | length)",

          "# HELP cardano_cc_seconds_per_epoch Environment constant: epochLength times slotLength from shelley genesis.",
          "# TYPE cardano_cc_seconds_per_epoch gauge",
          "cardano_cc_seconds_per_epoch{environment=\"\($env)\"} \($spe)"
        )
    ' <<< "$CS" > "$TMP"

    # Atomic publish via rename(2) on the same filesystem.
    mv "$TMP" "$OUT"
  '';
}
