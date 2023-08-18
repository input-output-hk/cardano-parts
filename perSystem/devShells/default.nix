{
  perSystem = {config, ...}: {
    cardano-parts.shell.defaultShell = "min";
    cardano-parts.shell.enableVars = false;
    cardano-parts.shell.extraPkgs = [config.packages.inputs-check];
  };
}
