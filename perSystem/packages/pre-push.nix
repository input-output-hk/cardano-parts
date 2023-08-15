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
      text = ''
        tput bold # bold
        tput setaf 5 # magenta
        echo >&2 'To skip, run git push with --no-verify.'
        tput sgr0 # reset

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
