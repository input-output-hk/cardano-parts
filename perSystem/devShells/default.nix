{
  perSystem = {
    lib,
    pkgs,
    config,
    self',
    ...
  }: {
    config.cardano-parts.shell.defaultShell = "min";
    config.cardano-parts.shell.enableVars = false;
  };
}
