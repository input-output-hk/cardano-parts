{
  perSystem = {
    lib,
    pkgs,
    system,
    config,
    ...
  }: {
    packages.pre-push = pkgs.writeShellApplication {
      name = "pre-push";
      runtimeInputs = with pkgs; [coreutils git gnugrep];
      text = ''
        tput bold # bold
        tput setaf 5 # magenta
        echo >&2 'To skip, run git push with --no-verify.'
        tput sgr0 # reset

        SECRETS_DIR="$(git rev-parse --show-toplevel)"/secrets
        if [ -d "$SECRETS_DIR" ]; then
          if [ "$(grep -rL '"data": "ENC' "$SECRETS_DIR" | wc -l)" != "0" ]; then
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
        nix build "''${checks[@]}"
      '';
    };
  };
}
