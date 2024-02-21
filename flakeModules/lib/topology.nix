lib: groupCfg:
# Argument `lib` is provided by the lib flakeModule topology option default:
#   flake.cardano-parts.lib.topology
#
# Argument groupCfg is provided by nixosModules whenever topology lib is required.
# GroupCfg is a mechanism to allow multiple cardano networks within a single repo.
with builtins;
with lib; rec {
  inherit (groupCfg) groupName groupPrefix;
  inherit (groupCfg.meta) domain;

  # Function composition
  compose = f: g: x: f (g x);

  # Compose a list of function, where fn `id` is required starting accumulator
  composeAll = builtins.foldl' compose id;

  # Generate a sorted list of group machine names
  groupMachines = nodes: sort (a: b: a < b) (filter (hasPrefix groupPrefix) (attrNames nodes));

  # Generate a p2p compatible producer attribute
  mkProducer = producer: nodes: let
    producerName =
      if isString producer
      then producer
      else producer.name;
    extraCfg =
      if isString producer
      then {}
      else removeAttrs producer ["name"];
  in
    {
      accessPoints = [
        {
          address = "${producerName}.${domain}";
          port = nodes.${producerName}.config.cardano-parts.perNode.meta.cardanoNodePort;
        }
      ];
    }
    // extraCfg;

  # Generate p2p edgeNodes from cardanoLib provided edgeNodes
  p2pEdgeNodes = map (edgeNode: {
    accessPoints = [
      {
        inherit (edgeNode) port;
        address = edgeNode.addr;
      }
    ];
  });

  # Shift a list by n
  shiftList = n: l: drop n l ++ (take n l);

  # Generate p2p producers using groupMachines filtered for self and allowing allowList infixes
  topoInfixFiltered = name: nodes: allowList:
    map (producer: mkProducer producer nodes) (
      filter (
        n:
          (n != name)
          && any (b: b) (map (allow: hasInfix allow n) allowList)
      ) (groupMachines nodes)
    );

  # Generate p2p producers using a list of machineNames which exist in nodes
  topoList = nodes: map (producer: mkProducer producer nodes);

  # Generate p2p producers using groupMachines filtered for self
  topoSimple = name: nodes:
    map (producer: mkProducer producer nodes) (filter (n: n != name) (groupMachines nodes));

  # Generate p2p producers using groupMachines filtered for self and applying a maximum producer limit
  topoSimpleMax = name: nodes: maxCount: let
    groupMachines' = groupMachines nodes;
    findPosition = name: l: (listToAttrs (imap0 (i: n: nameValuePair n i) l)).${name};
  in
    if maxCount >= (length groupMachines') - 1
    then topoSimple name nodes
    else
      map (producer: mkProducer producer nodes)
      (
        take maxCount
        (
          shiftList (
            (findPosition name groupMachines') + 1
          )
          groupMachines'
        )
      );
}
