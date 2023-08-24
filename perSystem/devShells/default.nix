{
  perSystem = {
    pkgs,
    config,
    ...
  }: {
    cardano-parts.shell.global.defaultShell = "min";
    cardano-parts.shell.global.enableVars = false;
    cardano-parts.shell.min.extraPkgs = with pkgs; [
      # For aws-ec2.json spec updates
      awscli2
      config.packages.inputs-check
    ];
  };
}
