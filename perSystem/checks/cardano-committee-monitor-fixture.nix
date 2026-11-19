# Golden-output check for the committee-state collector. Builds the same
# writeShellApplication the production unit uses, with a fixture-driven
# cardano-cli shim, then diffs against committee-state-expected.prom.
#
# When the fixture changes, regenerate the golden from the build failure
# diff and commit it alongside the fixture change.
{
  perSystem = {
    lib,
    pkgs,
    system,
    ...
  }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.cardano-committee-monitor-fixture = let
        # Require the actual ledger era: `latest` may still mean Conway
        # even when the connected node has entered Dijkstra.
        cardano-cli = pkgs.writeShellScriptBin "cardano-cli" ''
          case " $* " in
            *" query tip "*)
              echo "{\"era\":\"$TEST_ERA\",\"epoch\":0}"
              ;;
            *" committee-state "*)
              if [ "$1" != "''${TEST_ERA,,}" ]; then
                echo "fixture shim: wrong query era: $1" >&2
                exit 1
              fi
              cat ${../../flake/nixosModules/tests/committee-state-fixture.json}
              ;;
            *)
              echo "fixture shim: unsupported cardano-cli invocation: $*" >&2
              exit 64
              ;;
          esac
        '';
        collect = pkgs.callPackage ../../flakeModules/lib/cardano-committee-monitor-collect.nix {
          inherit cardano-cli;
        };
      in
        pkgs.runCommand "cardano-committee-monitor-fixture" {} ''
          export OUT="$TMPDIR/cardano-committee.prom"
          export ENVIRONMENT_NAME=preview
          export SECONDS_PER_EPOCH=86400
          # Dummies — production unit always sets these, so the check
          # asserts by their presence (and the shim ignores them).
          export CARDANO_NODE_NETWORK_ID=2
          export CARDANO_NODE_SOCKET_PATH=/dev/null

          for TEST_ERA in Conway Dijkstra; do
            export TEST_ERA
            ${collect}/bin/cardano-committee-monitor-collect
            diff -u ${../../flake/nixosModules/tests/committee-state-expected.prom} "$OUT"
          done
          touch "$out"
        '';
    };
}
