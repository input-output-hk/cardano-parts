# nixosModule: profile-cardano-faucet
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
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
    inherit (groupCfg) groupName groupFlake;
    inherit (opsLib) mkSopsSecret;

    groupOutPath = groupFlake.self.outPath;
    groupCfg = config.cardano-parts.cluster.group;
    opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;
  in {
    imports = [flake.config.flake.nixosModules.module-nginx-vhost-exporter];

    services = {
      cardano-faucet = {
        enable = true;
        openFirewallNginx = true;
      };

      nginx-vhost-exporter.enable = true;
    };

    sops.secrets = mkSopsSecret {
      secretName = "cardano-faucet.json";
      keyName = "${name}-faucet.json";
      inherit groupOutPath groupName;
      fileOwner = "cardano-faucet";
      fileGroup = "cardano-faucet";
      restartUnits = ["cardano-faucet.service"];
    };
  };
}
