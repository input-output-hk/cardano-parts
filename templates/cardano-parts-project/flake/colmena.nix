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
    t3a-medium.aws.instance.instance_type = "t3a.medium";
    m5a-large.aws.instance.instance_type = "m5a.large";

    # Helper fns:
    ebs = size: {aws.instance.root_block_device.volume_size = lib.mkDefault size;};

    # Helper defs:
    # delete.aws.instance.count = 0;

    # Cardano group assignments:
    group = name: {cardano-parts.cluster.group = config.flake.cardano-parts.cluster.groups.${name};};

    # Cardano-node modules for group deployment
    node = {
      imports = [
        # Base cardano-node service
        config.flake.cardano-parts.cluster.groups.default.meta.cardano-node-service

        # Config for cardano-node group deployments
        inputs.cardano-parts.nixosModules.profile-cardano-node-group
      ];
    };

    # Profiles
    topoSimple = {imports = [inputs.cardano-parts.nixosModules.profile-topology-simple];};
    pre = {imports = [inputs.cardano-parts.nixosModules.profile-pre-release];};

    smash = {
      imports = [
        config.flake.cardano-parts.cluster.groups.default.meta.cardano-smash-service
        inputs.cardano-parts.nixosModules.profile-cardano-smash
        {services.cardano-smash.acmeEmail = "devops@iohk.io";}
      ];
    };

    # Snapshots Profile: add this to a dbsync machine defn and deploy; remove once the snapshot is restored.
    # Snapshots for mainnet can be found at: https://update-cardano-mainnet.iohk.io/cardano-db-sync/index.html#13.1/
    # snapshot = {services.cardano-db-sync.restoreSnapshot = "$SNAPSHOT_URL";};

    # Roles
    rel = {imports = [inputs.cardano-parts.nixosModules.role-relay topoSimple];};
    bp = {imports = [inputs.cardano-parts.nixosModules.role-block-producer topoSimple];};

    dbsync = {
      imports = [
        config.flake.cardano-parts.cluster.groups.default.meta.cardano-node-service
        config.flake.cardano-parts.cluster.groups.default.meta.cardano-db-sync-service
        inputs.cardano-parts.nixosModules.profile-cardano-db-sync
        inputs.cardano-parts.nixosModules.profile-cardano-node-group
        inputs.cardano-parts.nixosModules.profile-cardano-postgres
      ];
    };

    faucet = {
      imports = [
        # TODO: Module import fixup for local services
        # config.flake.cardano-parts.cluster.groups.default.meta.cardano-faucet-service
        inputs.cardano-parts.nixosModules.service-cardano-faucet

        inputs.cardano-parts.nixosModules.profile-cardano-faucet
        {services.cardano-faucet.acmeEmail = "devops@iohk.io";}
      ];
    };
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

    preview1-bp-a-1 = {imports = [eu-central-1 t3a-small (ebs 40) (group "preview1") node bp];};
    preview1-rel-a-1 = {imports = [eu-central-1 t3a-small (ebs 40) (group "preview1") node rel];};
    preview1-rel-b-1 = {imports = [eu-west-1 t3a-small (ebs 40) (group "preview1") node rel];};
    preview1-rel-c-1 = {imports = [us-east-2 t3a-small (ebs 40) (group "preview1") node rel];};
    preview1-dbsync-a-1 = {imports = [eu-central-1 m5a-large (ebs 40) (group "preview1") dbsync smash];};
    preview1-faucet-a-1 = {imports = [eu-central-1 t3a-medium (ebs 40) (group "preview1") node faucet pre];};
  };
}
