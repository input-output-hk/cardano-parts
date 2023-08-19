{
  perSystem = {config, ...}: {
    cardano-parts.shell.global.defaultShell = "min";
    cardano-parts.shell.global.enableVars = false;
    cardano-parts.shell.min.extraPkgs = [config.packages.inputs-check];
  };
}
