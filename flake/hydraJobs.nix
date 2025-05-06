{
  config,
  lib,
  withSystem,
  ...
} @ parts: {
  flake.hydraJobs = lib.genAttrs config.systems (lib.flip withSystem (
    {
      config,
      pkgs,
      ...
    }: let
      jobs = {
        nixosConfigurations =
          lib.mapAttrs
          (_: {config, ...}: config.system.build.toplevel)
          parts.config.flake.nixosConfigurations;
        inherit (config) packages checks devShells;
      };
    in
      jobs
      // {
        required = pkgs.releaseTools.aggregate {
          name = "required";
          constituents = lib.collect lib.isDerivation jobs;
        };
      }
  ));
}
