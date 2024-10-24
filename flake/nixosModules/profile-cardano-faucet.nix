# nixosModule: profile-cardano-faucet
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-faucet.useSopsSecrets
#   config.services.nginx-vhost-exporter.address
#   config.services.nginx-vhost-exporter.enable
#   config.services.nginx-vhost-exporter.port
#
# Tips:
#   * This is a cardano-faucet profile add-on to the cardano-faucet nixos service module
#   * This module assists with configuring faucet secrets and metrics export
#   * The cardano-faucet nixos service module should still be imported separately
flake: {
  flake.nixosModules.profile-cardano-faucet = {
    config,
    lib,
    name,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption;
    inherit (lib.types) bool;

    inherit (groupCfg) groupName groupFlake;
    inherit (opsLib) mkSopsSecret;

    groupOutPath = groupFlake.self.outPath;
    groupCfg = config.cardano-parts.cluster.group;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

    cfg = config.services.cardano-faucet;
  in {
    imports = [flake.config.flake.nixosModules.module-nginx-vhost-exporter];

    options.services.cardano-faucet = {
      useSopsSecrets = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to use the default configurated sops secrets if true,
          or user deployed secrets if false.

          If false, the following required secret file will need to be provided
          to the target machine either by additional module code or out of
          band:

            /run/secrets/cardano-faucet
        '';
      };
    };

    config = {
      services = {
        cardano-faucet = {
          enable = true;
          openFirewallNginx = true;
        };

        nginx-vhost-exporter.enable = true;
      };

      sops.secrets = mkIf cfg.useSopsSecrets (mkSopsSecret {
        secretName = "cardano-faucet.json";
        keyName = "${name}-faucet.json";
        inherit groupOutPath groupName name;
        fileOwner = "cardano-faucet";
        fileGroup = "cardano-faucet";
        restartUnits = ["cardano-faucet.service"];
      });
    };
  };
}
