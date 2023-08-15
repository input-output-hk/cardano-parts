{
  self,
  inputs,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.common = moduleWithSystem ({system}: {config, ...}: {
    imports = [
      inputs.cardano-parts.inputs.sops-nix.nixosModules.default
      inputs.cardano-parts.inputs.auth-keys-hub.nixosModules.auth-keys-hub
    ];

    programs = {
      auth-keys-hub = {
        enable = true;
        package = inputs.cardano-parts.inputs.auth-keys-hub.packages.${system}.auth-keys-hub;
        github = {
          teams = [
            # Update auth-key-hub config for your project's access requirements
            "input-output-hk/UPDATE_ME"
          ];

          tokenFile = config.sops.secrets.github-token.path;
        };
      };
    };

    sops.defaultSopsFormat = "binary";

    # Create an encrypted github token with org:read access at:
    # ./secrets/github-token.enc
    # to enable auth-keys-hub functionality
    sops.secrets.github-token = {
      sopsFile = "${self}/secrets/github-token.enc";
      owner = config.programs.auth-keys-hub.user;
      inherit (config.programs.auth-keys-hub) group;
    };
  });
}
