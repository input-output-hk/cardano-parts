{
  config,
  lib,
  withSystem,
  ...
} @ parts:
with builtins;
with lib; {
  flake.hydraJobs = genAttrs config.systems (flip withSystem (
    {
      config,
      pkgs,
      ...
    }: let
      nixosCfgsNoIpModule =
        mapAttrs
        (name: cfg:
          if cfg.config.cardano-parts.perNode.generic.abortOnMissingIpModule
          then
            # Hydra will not have access to "ip-module" IPV4/IPV6 secrets
            # which are ordinarily only accessible from a deployer machine and
            # are not committed. In this case, hydra can still complete a
            # generic build without "ip-module" to check for other breakage.
            cfg.extendModules {
              modules = [
                (_: {
                  cardano-parts.perNode.generic = warn "Building machine ${name} without secret \"ip-module\" inclusion for hydraJobs CI" {
                    abortOnMissingIpModule = false;
                    warnOnMissingIpModule = false;
                  };
                })
              ];
            }
          else cfg)
        parts.config.flake.nixosConfigurations;

      jobs = {
        nixosConfigurations =
          mapAttrs
          (_: {config, ...}: config.system.build.toplevel)
          nixosCfgsNoIpModule;
        inherit (config) packages checks devShells;
      };
    in
      jobs
      // {
        required = pkgs.releaseTools.aggregate {
          name = "required";
          constituents = collect isDerivation jobs;
        };
      }
  ));
}
