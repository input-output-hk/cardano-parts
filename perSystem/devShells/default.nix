{
  perSystem = {
    lib,
    pkgs,
    config,
    self',
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        deadnix
        just
        nushell
        statix
      ];

      shellHook = ''
        ln -sf ${lib.getExe self'.packages.pre-push} .git/hooks/
        ln -sf ${config.treefmt.build.configFile} treefmt.toml
      '';
    };
  };
}
