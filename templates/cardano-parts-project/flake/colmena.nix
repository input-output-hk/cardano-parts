{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (config.flake) nixosModules nixosConfigurations;
in {
  flake.colmena = let
    # Region defs:
    eu-central-1.aws.region = "eu-central-1";
    eu-west-1.aws.region = "eu-west-1";
    us-east-2.aws.region = "us-east-2";

    # Instance defs:
    t3a-small.aws.instance.instance_type = "t3a.small";

    # Helper fns:
    ebs = size: {aws.instance.root_block_device.volume_size = lib.mkDefault size;};

    # Helper defs:
    # delete.aws.instance.count = 0;

    # Cardano group assignments:
    preview1 = {cardano-parts.cluster.group = config.flake.cardano-parts.cluster.group.preview1;};

    # Cardano-node modules for group deployment
    node = {
      imports = [
        # Base cardano-node service
        config.flake.cardano-parts.cluster.group.default.meta.cardano-node-service

        # Config for cardano-node group deployments
        inputs.cardano-parts.nixosModules.module-cardano-node-group

        # Default group deployment topology
        topoSimple
      ];
    };

    # Profiles
    topoSimple = {imports = [inputs.cardano-parts.nixosModules.profile-topology-simple];};
    # pre = {imports = [inputs.cardano-parts.nixosModules.profile-pre-release];};

    # Roles
    rel = {imports = [inputs.cardano-parts.nixosModules.role-relay];};
    bp = {imports = [inputs.cardano-parts.nixosModules.role-block-producer];};
  in {
    meta = {
      nixpkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
      };

      nodeSpecialArgs =
        lib.foldl'
        (acc: node: let
          instanceType = node: nixosConfigurations.${node}.config.aws.instance.instance_type;
        in
          lib.recursiveUpdate acc {
            ${node} = {
              nodeResources = {
                inherit
                  (config.flake.cardano-parts.aws.ec2.spec.${instanceType node})
                  provider
                  coreCount
                  cpuCount
                  memMiB
                  nodeType
                  threadsPerCore
                  ;
              };
            };
          })
        {} (builtins.attrNames nixosConfigurations);
    };

    defaults.imports = [
      inputs.cardano-parts.nixosModules.module-aws-ec2
      inputs.cardano-parts.nixosModules.module-cardano-parts
      inputs.cardano-parts.nixosModules.profile-basic
      inputs.cardano-parts.nixosModules.profile-common
      inputs.cardano-parts.nixosModules.profile-grafana-agent
      nixosModules.common
    ];

    preview1-bp-a-1 = {imports = [eu-central-1 t3a-small (ebs 40) preview1 node bp];};
    preview1-rel-a-1 = {imports = [eu-central-1 t3a-small (ebs 40) preview1 node rel];};
    preview1-rel-b-1 = {imports = [eu-west-1 t3a-small (ebs 40) preview1 node rel];};
    preview1-rel-c-1 = {imports = [us-east-2 t3a-small (ebs 40) preview1 node rel];};
  };
}
