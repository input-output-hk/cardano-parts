# nixosModule: role-relay
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
{
  flake.nixosModules.role-relay = nixos: let
    inherit (nixos.config.cardano-parts.perNode.meta) cardanoNodePort;
  in {
    key = ./role-relay.nix;

    config.networking.firewall = {allowedTCPPorts = [cardanoNodePort];};
  };
}
