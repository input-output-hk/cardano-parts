{
  perSystem = {inputs'}: {
    cardano-parts.shell.global.defaultShell = "ops";
    cardano-parts.shell.global.extraPkgs = [inputs'.cardano-parts.packages.pre-push];
  };
}
