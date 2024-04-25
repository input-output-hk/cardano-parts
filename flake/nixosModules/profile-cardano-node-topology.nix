# nixosModule: profile-cardano-node-topology
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-node-topology.allowList
#   config.services.cardano-node-topology.edgeNodes
#   config.services.cardano-node-topology.enableProducers
#   config.services.cardano-node-topology.enablePublicProducers
#   config.services.cardano-node-topology.extraCfgInfix
#   config.services.cardano-node-topology.extraCfgSimple
#   config.services.cardano-node-topology.extraCfgSimpleMax
#   config.services.cardano-node-topology.extraNodeListProducers
#   config.services.cardano-node-topology.extraNodeListPublicProducers
#   config.services.cardano-node-topology.extraProducers
#   config.services.cardano-node-topology.extraPublicProducers
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
    with builtins;
    with lib; let
      inherit (types) attrs bool either enum ints listOf nullOr str;
      inherit (config.cardano-parts.cluster.group.meta) environmentName;
      inherit (config.cardano-parts.perNode.lib) cardanoLib topologyLib;
      inherit (cardanoLib.environments.${environmentName}) edgeNodes;

      verboseTrace = desc: v: traceVerbose "${name}: is using ${desc} of: ${toJSON v}" v;

      topologyFns = with topologyLib; {
        edge =
          # This can be simplified upon all machines deployed >= node 8.9.0
          if cfgNode ? bootstrapPeers && cfgNode.bootstrapPeers != null
          then []
          else p2pEdgeNodes cfg.edgeNodes;

        empty = [];

        list = topoList {inherit (cfg) nodes nodeList;};

        infix = topoInfixFiltered {
          inherit (cfg) name nodes allowList;
          # For intra-cluster peer members, default to trustable localRoots
          extraCfg = {trustable = true;} // cfg.extraCfgInfix;
        };

        simple = topoSimple {
          inherit (cfg) name nodes;
          # For intra-cluster peer members, default to trustable localRoots
          extraCfg = {trustable = true;} // cfg.extraCfgSimple;
        };

        simpleMax = topoSimpleMax {
          inherit (cfg) name nodes maxCount;
          # For intra-cluster peer members, default to trustable localRoots
          extraCfg = {trustable = true;} // cfg.extraCfgSimpleMax;
        };
      };

      roles = with topologyLib; {
        edge = {
          producers = [];
          publicProducers = topologyFns.edge ++ extraNodeListPublicProducers ++ extraPublicProducers;
        };

        relay = {
          producers = topoInfixFiltered {
            inherit (cfg) name nodes;
            allowList = cfg.infixProducersForRel;
            # For intra-cluster peer members, default to trustable localRoots
            extraCfg = {trustable = true;} // cfg.extraCfgInfix;
          };
          publicProducers = topologyFns.edge ++ extraNodeListPublicProducers ++ extraPublicProducers;
        };

        bp = {
          producers = topoInfixFiltered {
            inherit (cfg) name nodes;
            allowList = cfg.infixProducersForBp;
            # For intra-cluster peer members, default to trustable localRoots
            extraCfg = {trustable = true;} // cfg.extraCfgInfix;
          };

          # These are also set from the role-block-producer nixos module
          extraNodeConfig = {
            PeerSharing = false;
            TargetNumberOfRootPeers = 100;
          };
          publicProducers = mkForce (extraNodeListPublicProducers ++ extraPublicProducers);
          usePeersFromLedgerAfterSlot = -1;
        };
      };

      mkBasicProducers = producer: let
        extraCfg = removeAttrs producer ["address" "port"];
      in
        {
          accessPoints = [{inherit (producer) address port;}];
        }
        // extraCfg;

      extraNodeListProducers = topologyLib.topoList {
        inherit (cfg) nodes;
        nodeList = cfg.extraNodeListProducers;
      };

      extraNodeListPublicProducers = topologyLib.topoList {
        inherit (cfg) nodes;
        nodeList = cfg.extraNodeListPublicProducers;
      };

      extraProducers = map mkBasicProducers cfg.extraProducers;
      extraPublicProducers = map mkBasicProducers cfg.extraPublicProducers;

      cfgNode = config.services.cardano-node;
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

          extraCfgInfix = mkOption {
            type = attrs;
            default = {};
            description = ''
              Any extra config which should be applied to infix topology function generated results.

              Note that intra-cluster localRoots defined with topoInfixFiltered will be automatically set trustable.
            '';
          };

          extraCfgSimple = mkOption {
            type = attrs;
            default = {};
            description = ''
              Any extra config which should be applied to simple topology function generated results.

              Note that intra-cluster localRoots defined with topoSimple will be automatically set trustable.
            '';
          };

          extraCfgSimpleMax = mkOption {
            type = attrs;
            default = {};
            description = ''
              Any extra config which should be applied to simpleMax topology function generated results.

              Note that intra-cluster localRoots defined with topoSimpleMax will be automatically set trustable.
            '';
          };

          extraNodeListProducers = mkOption {
            type = listOf (either str attrs);
            default = [];
            description = ''
              Extra producers which will be added to any role or function.

              Provided as a list of either strings of Colmena machine names or attribute sets
              each of which contains at least a name key with a Colmena machine name:
              [
                "$COLMENA_MACHINE_1"
                {name = "$COLMENA_MACHINE_2"; ...}
              ]

              This is intended to be a simple way to inject extra producers from node names.

              When declaring an attribute set list item, any additional attributes beyond the name
              will be appended as extra config to the accessPoints list.

              If further customization is required, add the extra producers directly to the
              services.cardano-node.producers option.
            '';
          };

          extraNodeListPublicProducers = mkOption {
            type = listOf (either str attrs);
            default = [];
            description = ''
              Extra public producers which will be added to any role or function.

              Provided as a list of either strings of Colmena machine names or attribute sets
              each of which contains at least a name key with a Colmena machine name:
              [
                "$COLMENA_MACHINE_1"
                {name = "$COLMENA_MACHINE_2"; ...}
              ]

              This is intended to be a simple way to inject extra public producers from node names.

              When declaring an attribute set list item, any additional attributes beyond the name
              will be appended as extra config to the accessPoints list.

              If further customization is required, add the extra public producers directly to the
              services.cardano-node.publicProducers option.
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
                ...
              }

              This is intended to be a simple way to inject basic form extra producers.

              Additional attributes beyond address and port in the attribute set will be appended
              as extra config to the accessPoint list.

              If further customization is required add the extra producers directly to the
              services.cardano-node.producers option.
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
                ...
              }

              This is intended to be a simple way to inject basic form extra public producers.

              Additional attributes beyond address and port in the attribute set will be appended
              as extra config to the accessPoints list.

              If further customization is required, add the extra public producers directly to the
              services.cardano-node.publicProducers option.
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
            type = listOf (either str attrs);
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
            type = enum ["edge" "empty" "infix" "list" "simple" "simpleMax"];
            default = "simple";
            description = "The topology function to use for producers.";
          };

          publicProducerTopologyFn = mkOption {
            type = enum ["edge" "empty" "infix" "list" "simple" "simpleMax"];
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
        services.cardano-node =
          {
            extraNodeConfig = mkIf (cfg.role == "bp") roles.${cfg.role}.extraNodeConfig;

            producers = mkIf (cfg.role != null || cfg.enableProducers) (
              if cfg.role != null
              then verboseTrace "producers" (roles.${cfg.role}.producers ++ extraNodeListProducers ++ extraProducers)
              else verboseTrace "producers" (topologyFns.${cfg.producerTopologyFn} ++ extraNodeListProducers ++ extraProducers)
            );

            publicProducers = mkIf (cfg.role != null || cfg.enablePublicProducers) (
              # Extra node list public producers and public producers for roles are included in the role defns due to selective mkForce use
              if cfg.role != null
              then verboseTrace "publicProducers" roles.${cfg.role}.publicProducers
              else verboseTrace "publicProducers" (topologyFns.${cfg.publicProducerTopologyFn} ++ extraNodeListPublicProducers ++ extraPublicProducers)
            );

            usePeersFromLedgerAfterSlot = mkIf (cfg.role == "bp") roles.${cfg.role}.usePeersFromLedgerAfterSlot;
          }
          # This can be simplified upon all machines deployed >= node 8.9.0
          // optionalAttrs (cfgNode ? bootstrapPeers) {
            bootstrapPeers =
              mkIf (cfg.role == "bp")
              null;
          };
      };
    };
}
