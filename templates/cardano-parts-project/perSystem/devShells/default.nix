{
  perSystem = {config, ...}: {
    cardano-parts.shell.global.defaultShell = "ops";
    cardano-parts.shell.global.extraPkgs = [config.packages.pre-push];
  };
}
