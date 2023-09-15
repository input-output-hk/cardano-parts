# nixosModule: profile-topology-simple
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
{
  flake.nixosModules.profile-topology-simple = nixos: let
    inherit (nixos.config.cardano-parts.cluster.group.meta) environmentName;
    inherit (nixos.config.cardano-parts.perNode.lib) cardanoLib topologyLib;
    inherit (cardanoLib.environments.${environmentName}) edgeNodes;
  in {
    services.cardano-node = {
      producers = topologyLib.topoSimple nixos.name nixos.nodes;
      publicProducers = topologyLib.p2pEdgeNodes edgeNodes;
    };
  };
}
