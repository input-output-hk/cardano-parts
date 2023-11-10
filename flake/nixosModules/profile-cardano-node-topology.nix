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
          publicProducers = topologyFns.edge ++ extraNodeListPublicProducers ++ extraPublicProducers;
        };

        relay = {
          producers = topoInfixFiltered cfg.name cfg.nodes cfg.infixProducersForRel;
          publicProducers = topologyFns.edge ++ extraNodeListPublicProducers ++ extraPublicProducers;
        };

        bp = {
          producers = topoInfixFiltered cfg.name cfg.nodes cfg.infixProducersForBp;

          # These are also set from the role-block-producer nixos module
          publicProducers = mkForce (extraNodeListProducers ++ extraPublicProducers);
          usePeersFromLedgerAfterSlot = -1;
        };
      };

      mkBasicProducers = producer: {
        accessPoints = [{inherit (producer) address port;}];
      };

      extraNodeListProducers = topologyLib.topoList cfg.nodes cfg.extraNodeListProducers;
      extraNodeListPublicProducers = topologyLib.topoList cfg.nodes cfg.extraNodeListPublicProducers;

      extraProducers = map mkBasicProducers cfg.extraProducers;
      extraPublicProducers = map mkBasicProducers cfg.extraPublicProducers;

      cfg = config.services.cardano-node-topology;
    in {
      options = {
        services.cardano-node-topology = {
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

          extraNodeListProducers = mkOption {
            type = listOf str;
            default = [];
            description = ''
              Extra producers which will be added to any role or function.

              Provided as list of strings of Colmena machine names:
              [
                "$COLMENA_MACHINE_1"
                "$COLMENA_MACHINE_2"
              ]

              This is intended to be a simple way to inject extra producers from relay node names.
              If specifying valency or advertising, or custom grouping is required,
              add the extra producers directly to the services.cardano-node.producers option.
            '';
          };

          extraNodeListPublicProducers = mkOption {
            type = listOf str;
            default = [];
            description = ''
              Extra public producers which will be added to any role or function.

              Provided as list of strings of Colmena machine names:
              [
                "$COLMENA_MACHINE_1"
                "$COLMENA_MACHINE_2"
              ]

              This is intended to be a simple way to inject extra public producers from relay node names.
              If specifying valency or advertising, or custom grouping is required,
              add the extra public producers directly to the services.cardano-node.publicProducers option.
            '';
          };

          extraProducers = mkOption {
            type = listOf attrs;
            default = [];
            description = ''
              Extra producers which will be added to any role or function.

              Provided as list of attributes of:
              {
                address = "$ADDRESS";
                port = $PORT;
              }

              This is intended to be a simple way to inject basic form extra producers.
              If specifying valency or advertising, or custom grouping is required,
              add the extra producers directly to the services.cardano-node.producers option.
            '';
          };

          extraPublicProducers = mkOption {
            type = listOf attrs;
            default = [];
            description = ''
              Extra public producers which will be added to any role or function.

              Provided as list of attributes of:
              {
                address = "$ADDRESS";
                port = $PORT;
              }

              This is intended to be a simple way to inject basic form extra public producers.
              If specifying valency or advertising, or custom grouping is required,
              add the extra public producers directly to the services.cardano-node.publicProducers option.
            '';
          };

          infixProducersForBp = mkOption {
            type = listOf str;
            default = ["-rel-"];
            description = ''
              The infix allow list for generating producers for the block producer role.
            '';
          };

          infixProducersForRel = mkOption {
            type = listOf str;
            default = ["-bp-" "-rel-"];
            description = ''
              The infix allow list for generating producers for the relay role.
            '';
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
            default = attrNames cfg.nodes;
            description = ''
              The node list for topology functions requiring it.

              Applicable to topology functions: list.
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
            then roles.${cfg.role}.producers ++ extraNodeListProducers ++ extraProducers
            else topologyFns.${cfg.producerTopologyFn} ++ extraNodeListProducers ++ extraProducers
          );

          publicProducers = mkIf (cfg.role != null || cfg.enablePublicProducers) (
            # Extra node list public producers and public producers for roles are included in the role defns due to selective mkForce use
            if cfg.role != null
            then roles.${cfg.role}.publicProducers
            else topologyFns.${cfg.publicProducerTopologyFn} ++ extraNodeListPublicProducers ++ extraPublicProducers
          );

          usePeersFromLedgerAfterSlot =
            mkIf (cfg.role == "bp")
            roles.${cfg.role}.usePeersFromLedgerAfterSlot;
        };
      };
    };
}
