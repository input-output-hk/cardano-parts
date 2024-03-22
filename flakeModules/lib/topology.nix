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

    # An addressType attr can be passed as extraCfg and will have the following effect on producer generation, when declared as:
    #   fqdn            ==> will record the producer as the nixosConfiguration machine name with cluster DNS suffix
    #   namePrivateIpv4 ==> will record the nixosConfiguration machine name with a `-private-ipv4` suffix
    #   namePublicIpv4  ==> will record the nixosConfiguration machine name with a `-public-ipv4` suffix
    #   privateIpv4     ==> will record the actual private ipv4
    #   publiceIpv4     ==> will record the actual public ipv4
    #
    # Note that the use of addressType of name[Public|Private]Ipv4 will fail unless there is a corresponding /etc/hosts entry.
    # The hosts configuration, by default, will only be set up with private and public ipv4 for machines in the same cardano-parts group
    # assuming that the nixosModules ips-module created locally in each downstream cardano-parts repo is available.
    #
    # See the config.cardano-parts.perNode.meta.hostsList option in module-cardano-parts for details.
    addressType =
      if extraCfg ? addressType
      then
        if elem extraCfg.addressType ["fqdn" "namePrivateIpv4" "namePublicIpv4" "privateIpv4" "publicIpv4"]
        then extraCfg.addressType
        else abort "ABORT: producer addressType must be one of: fqdn, namePrivateIpv4, namePublicIpv4, privateIpv4, publicIpv4"
      else "namePublicIpv4";

    addressSelector = {
      inherit (nodes.${producerName}.config.ips) privateIpv4 publicIpv4;
      fqdn = "${producerName}.${domain}";
      name = producerName;
      namePrivateIpv4 = "${producerName}.private-ipv4";
      namePublicIpv4 = "${producerName}.public-ipv4";
    };
  in
    {
      accessPoints = [
        {
          address = addressSelector.${addressType};
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
  topoInfixFiltered = {
    name,
    nodes,
    allowList,
    extraCfg ? {},
  }:
    map (producer: mkProducer ({name = producer;} // extraCfg) nodes) (
      filter (
        n:
          (n != name)
          && any (b: b) (map (allow: hasInfix allow n) allowList)
      ) (groupMachines nodes)
    );

  # Generate p2p producers using a list of machineNames which exist in nodes
  # The nodeList may be provided as a list of either strings of Colmena machine names
  # or attribute sets each of which contains at least a name key with a Colmena machine name:
  # [
  #   "$COLMENA_MACHINE_1"
  #   {name = "$COLMENA_MACHINE_2"; ...}
  # ]
  topoList = {
    nodes,
    nodeList,
    extraCfg ? {},
  }:
    map (producer:
      mkProducer (
        if isString producer
        then {name = producer;} // extraCfg
        else producer // extraCfg
      )
      nodes)
    nodeList;

  # Generate p2p producers using groupMachines filtered for self
  topoSimple = {
    name,
    nodes,
    extraCfg ? {},
  }:
    map (producer: mkProducer ({name = producer;} // extraCfg) nodes) (filter (n: n != name) (groupMachines nodes));

  # Generate p2p producers using groupMachines filtered for self and applying a maximum producer limit
  topoSimpleMax = {
    name,
    nodes,
    maxCount,
    extraCfg ? {},
  }: let
    groupMachines' = groupMachines nodes;
    findPosition = name: l: (listToAttrs (imap0 (i: n: nameValuePair n i) l)).${name};
  in
    if maxCount >= (length groupMachines') - 1
    then topoSimple name nodes
    else
      map (producer: mkProducer ({name = producer;} // extraCfg) nodes)
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
