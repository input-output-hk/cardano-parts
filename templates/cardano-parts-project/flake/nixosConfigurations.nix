{
  inputs,
  config,
  ...
}: {
  flake.nixosConfigurations = (inputs.cardano-parts.inputs.colmena.lib.makeHive config.flake.colmena).nodes;
}
