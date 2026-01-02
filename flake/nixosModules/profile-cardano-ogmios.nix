# nixosModule: profile-cardano-ogmios
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-ogmios.* - all upstream cardano-ogmios service options
#
# Tips:
#   * This is a cardano-ogmios profile that configures the upstream cardano-ogmios nixos service module
#   * The upstream cardano-ogmios nixos service module should still be imported separately
#   * The profile automatically configures: package, nodeSocket, and nodeConfig based on cardano-parts settings
#   * Ogmios will connect to cardano-node instance 0 by default
#   * To enable, set: services.cardano-ogmios.enable = true;
flake: {
  flake.nixosModules.profile-cardano-ogmios = {
    config,
    pkgs,
    lib,
    ...
  }:
    with lib; let
      inherit (config.cardano-parts.perNode.lib.cardanoLib) environments;
      inherit (config.cardano-parts.cluster.group.meta) environmentName;
    in {
      key = ./profile-cardano-ogmios.nix;

      config = {
        services.cardano-ogmios = {
          # Configure package from cardano-parts (set unconditionally to avoid evaluation errors)
          package = mkDefault config.cardano-parts.perNode.pkgs.cardano-ogmios;

          # Connect to cardano-node instance 0 socket
          nodeSocket = mkDefault (config.services.cardano-node.socketPath 0);

          nodeConfig = mkDefault (pkgs.writeText "ogmios-node-config.json"
            (builtins.toJSON environments.${environmentName}.nodeConfig));
        };

        # Ensure ogmios user has access to cardano-node socket (only when enabled)
        users = mkIf config.services.cardano-ogmios.enable {
          groups.cardano-ogmios = {};
          users.cardano-ogmios = {
            extraGroups = ["cardano-node"];
            group = "cardano-ogmios";
            isSystemUser = true;
          };
        };
      };
    };
}
