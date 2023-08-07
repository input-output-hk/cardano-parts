{inputs, ...} @ parts: {
  perSystem = {
    pkgs,
    system,
    lib,
    config,
    ...
  }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.test = inputs.nixpkgs.lib.nixos.runTest ({nodes, ...}: let
        inherit (parts.config.flake.nixosModules) common;
      in {
        name = "test";

        hostPkgs = pkgs;

        defaults = {...}: {
          imports = [common];
        };

        nodes = {
          # ci1 = {...}: {
          #   imports = [];
          #   networking.firewall.allowedTCPPorts = [];
          # };

          # ci2 = {};
        };

        testScript = ''
        '';
      });
    };
}
