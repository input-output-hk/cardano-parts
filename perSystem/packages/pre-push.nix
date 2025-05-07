{
  perSystem = {
    lib,
    pkgs,
    system,
    config,
    ...
  }:
    with lib; {
      packages.pre-push = pkgs.writeShellApplication {
        name = "pre-push";
        runtimeInputs = with pkgs; [coreutils gitMinimal gnugrep];
        meta.description = "A pre-push repo check for required secrets encryption, linting and formatting";
        text = ''
          IPURPLE='\e[1;95m'
          IWHITE='\e[1;97m'
          IREDBK='\e[0;101m'
          NC='\e[0m'
          echo -e >&2 "''${IPURPLE}To skip, run git push with --no-verify.''${NC}"

          WARN() {
            echo -e "''${IWHITE}''${IREDBK}   *** WARNING: ***   ''${NC}"
          }
          TOP=$(git rev-parse --show-toplevel)
          IPS_FN="ips-DONT-COMMIT.nix"
          IP_SECRETS="''${TOP}/flake/nixosModules/$IPS_FN"

          if [ "$(git log -m --follow --full-history "$IP_SECRETS" 2> /dev/null | wc -c)" != "0" ]; then
            echo
            WARN
            echo
            echo "For the current repo directory of $TOP:"
            echo "    The flake/nixosModules/$IPS_FN file has been committed, but it should not be."
            echo "    Remove this file from the commit history and try again."
            echo
            echo "Commit history containing this file:"
            git log -m --follow --full-history "$IP_SECRETS"
            exit 1
          fi

          SECRETS_DIR="''${TOP}/secrets"
          if [ -d "$SECRETS_DIR" ]; then
            if [ "$(grep -rL '"data": "ENC' "$SECRETS_DIR" | wc -l)" != "0" ]; then
              echo
              WARN
              echo
              echo "The following secrets/ files appear to be un-encrypted or not binary encrypted:"
              grep -rL '"data": "ENC' "$SECRETS_DIR"
              exit 1
            fi
          fi

          declare -a checks
          for check in ${lib.escapeShellArgs (builtins.attrNames config.checks)}; do
            checks+=(.#checks.${lib.escapeShellArg system}."$check")
          done

          set -x
          nix build "''${checks[@]}" --no-link
        '';
      };
    };
}
