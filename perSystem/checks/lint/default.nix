{self, ...}: {
  perSystem = {pkgs, ...}: {
    checks.lint =
      pkgs.runCommand "lint" {
        nativeBuildInputs = with pkgs; [
          just
          deadnix
          nushell
          statix
        ];
      } ''
        set -euo pipefail

        cd ${self}
        just lint
        touch $out
      '';
  };
}
