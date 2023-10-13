# nixosModule: profile-cardano-node-topology
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-node-topology.allowList
#   config.services.cardano-node-topology.edgeNodes
#   config.services.cardano-node-topology.enableProducers
#   config.services.cardano-node-topology.enablePublicProducers
#   config.services.cardano-node-topology.maxCount
#   config.services.cardano-node-topology.name
#   config.services.cardano-node-topology.nodeList
#   config.services.cardano-node-topology.nodes
#   config.services.cardano-node-topology.producerTopologyFn
#   config.services.cardano-node-topology.publicProducerTopologyFn
#   config.services.cardano-node-topology.role
#
# Tips:
#  * This nixos module profile assists with easy configuration of cardano-node topology for common use cases
{
  flake.nixosModules.profile-cardano-node-topology = {
    config,
    lib,
    name,
    nodes,
    ...
  }:
    with lib; let
      inherit (types) attrs bool enum ints listOf nullOr str;
      inherit (config.cardano-parts.cluster.group.meta) environmentName;
      inherit (config.cardano-parts.perNode.lib) cardanoLib topologyLib;
      inherit (cardanoLib.environments.${environmentName}) edgeNodes;

      topologyFns = with topologyLib; {
        edge = p2pEdgeNodes cfg.edgeNodes;
        list = topoList cfg.nodes cfg.nodeList;
        infix = topoInfixFiltered cfg.name cfg.nodes cfg.allowList;
        simple = topoSimple cfg.name cfg.nodes;
        simpleMax = topoSimpleMax cfg.name cfg.nodes cfg.maxCount;
      };

      roles = with topologyLib; {
        edge = {
          producers = [];
          publicProducers = topologyFns.edge;
        };

        relay = {
          producers = topoInfixFiltered cfg.name cfg.nodes ["-bp-" "-rel-"];
          publicProducers = topologyFns.edge;
        };

        bp = {
          producers = topoInfixFiltered cfg.name cfg.nodes ["-rel-"];
          publicProducers = topologyFns.edge;
        };
      };

      cfg = config.services.cardano-topology;
    in {
      options = {
        services.cardano-topology = {
          allowList = mkOption {
            type = listOf str;
            default = [];
            description = ''
              The allowList for topology functions requiring it.

              Applicable to topology functions: infix.
            '';
          };

          edgeNodes = mkOption {
            type = listOf attrs;
            default = edgeNodes;
            description = ''
              The edgeNodes for topology functions requiring it.

              Applicable to topology functions: edge.
            '';
          };

          enableProducers = mkOption {
            type = bool;
            default = true;
            description = "Whether to enable producers by default.";
          };

          enablePublicProducers = mkOption {
            type = bool;
            default = true;
            description = "Whether to enable public producers by default.";
          };

          maxCount = mkOption {
            type = ints.positive;
            default = 0;
            description = ''
              The maxCount for topology functions requiring it.

              Applicable to topology functions: simpleMax.
            '';
          };

          name = mkOption {
            type = str;
            default = name;
            description = "The name machine name for self-filtering for topology functions requiring it.";
          };

          nodeList = mkOption {
            type = listOf str;
            default = attrNames nodes;
            description = ''
              The node list for topology functions requiring it.

              Applicable to topology functions: simpleMax.
            '';
          };

          nodes = mkOption {
            type = attrs;
            default = nodes;
            description = "The node attributes for topology functions requiring it.";
          };

          producerTopologyFn = mkOption {
            type = enum ["edge" "infix" "list" "simple" "simpleMax"];
            default = "simple";
            description = "The topology function to use for producers.";
          };

          publicProducerTopologyFn = mkOption {
            type = enum ["edge" "infix" "list" "simple" "simpleMax"];
            default = "edge";
            description = "The topology function to use for public producers.";
          };

          role = mkOption {
            type = nullOr (enum ["bp" "edge" "relay"]);
            default = null;
            description = ''
              A quick topology set up option for common pre-canned configuration.

              If a role is declared, the pre-canned options will be used.
              If no role is declared (null), the more granular options in the module apply.
            '';
          };
        };
      };

      config = {
        services.cardano-node = {
          producers = mkIf (cfg.role != null || cfg.enableProducers) (
            if cfg.role != null
            then roles.${cfg.role}.producers
            else topologyFns.${cfg.producerTopologyFn}
          );

          publicProducers = mkIf (cfg.role != null || cfg.enablePublicProducers) (
            if cfg.role != null
            then roles.${cfg.role}.publicProducers
            else topologyFns.${cfg.publicProducerTopologyFn}
          );
        };
      };
    };
}
