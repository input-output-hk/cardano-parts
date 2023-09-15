# nixosModule: module-common
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.programs.auth-keys-hub.<...>
#   config.sops.<...>
#
# Tips:
# * Repository authentication permissions and repository token secret
# will typically be declared in the consuming repo.
#
# * Example:
#   ../../templates/cardano-parts-project/flake/nixosModules/common.nix
{
  inputs,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.module-common = moduleWithSystem ({system}: {
    config,
    lib,
    ...
  }: {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.auth-keys-hub.nixosModules.auth-keys-hub
    ];

    # Sops-secrets service provides a systemd hook for other services
    # needing to be restarted after new secrets are pushed.
    #
    # Example usage:
    #   systemd.services.<name> = {
    #     after = ["sops-secrets.service"];
    #     wants = ["sops-secrets.service"];
    #   };
    #
    # Also, on boot SOPS runs in stage 2 without networking.
    # For repositories using KMS sops secrets, this prevent KMS from working,
    # so we repeat the activation script until decryption succeeds.
    systemd.services.sops-secrets = {
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];

      script = config.system.activationScripts.setupSecrets.text or "true";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    programs = {
      auth-keys-hub = {
        enable = lib.mkDefault true;
        package = inputs.auth-keys-hub.packages.${system}.auth-keys-hub;
      };
    };

    sops.defaultSopsFormat = "binary";
  });
}
