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
    ...
  }:
    with builtins;
    with lib; let
      inherit (groupCfg) groupName groupFlake;

      groupOutPath = groupFlake.self.outPath;
      pathPrefix = "${groupOutPath}/secrets/groups/${groupName}/deploy/";
      trimStorePrefix = path: last (split "/nix/store/[^/]+/" path);
      verboseTrace = key: traceVerbose ("${name}: using " + (trimStorePrefix key));

      owner = "cardano-faucet";
      group = "cardano-faucet";

      mkSopsSecret = secretName: key: {
        ${secretName} = verboseTrace (pathPrefix + key) {
          inherit owner group;
          sopsFile = pathPrefix + key;
        };
      };

      groupCfg = config.cardano-parts.cluster.group;
    in {
      imports = [flake.config.flake.nixosModules.module-nginx-vhost-exporter];

      services = {
        cardano-faucet = {
          enable = true;
          openFirewallNginx = true;
        };

        nginx-vhost-exporter.enable = true;
      };

      systemd.services.cardano-faucet = {
        after = ["sops-secrets.service"];
        wants = ["sops-secrets.service"];
      };

      sops.secrets = mkSopsSecret "cardano-faucet.json" "${name}-faucet.json";
    };
}
