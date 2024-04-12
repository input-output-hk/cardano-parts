flake: {
  flake.nixosModules.ip-module-check = {
    config,
    lib,
    ...
  }: let
    inherit (lib) optional;
    inherit (flake.config.flake) nixosModules;

    cfgGeneric = flake.config.flake.cardano-parts.cluster.infra.generic;

    msg = ''

      The nixosModule "ip-module" which most clusters use is missing.
        Builds or deployed software and services may break.
        Generate the module with: `just update-ips`
    '';
  in {
    imports = optional (nixosModules ? ip-module) nixosModules.ip-module;

    warnings =
      optional (!(nixosModules ? ip-module) && cfgGeneric.warnOnMissingIpModule)
      (msg
        + ''

          If you know what you are doing and have a special edge case, this warning may be disabled by setting:
            flake.cardano-parts.cluster.infra.generic.warnOnMissingIpModule = false'');

    assertions = [
      {
        assertion = (nixosModules ? ip-module) || !(nixosModules ? ip-module) && !cfgGeneric.abortOnMissingIpModule;
        message =
          msg
          + ''

            If you know what you are doing and have a special edge case, this abort may be disabled by setting:
              flake.cardano-parts.cluster.infra.generic.abortOnMissingIpModule = false'';
      }
    ];
  };
}
