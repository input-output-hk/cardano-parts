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

    # Instance defs:
    t3a-small.aws.instance.instance_type = "t3a.small";

    # OS defs:
    nixos-23-05.system.stateVersion = "23.05";

    # Helper defs:
    # delete.aws.instance.count = 0;

    # Helper fns:
    ebs = size: {aws.instance.root_block_device.volume_size = lib.mkDefault size;};
  in {
    meta = {
      nixpkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
      };

      # Make node spec info available to nixosModules
      nodeSpecialArgs =
        lib.foldl'
        (acc: node: let
          instanceType = node: nixosConfigurations.${node}.config.aws.instance.instance_type;
        in
          lib.recursiveUpdate acc {
            ${node} = {
              nodeResources = {
                inherit
                  (config.flake.cardano-parts.aws-ec2.spec.${instanceType node})
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
      inputs.cardano-parts.nixosModules.aws-ec2
      inputs.cardano-parts.nixosModules.basic
      inputs.cardano-parts.nixosModules.cardano-parts
      nixosModules.common
      nixos-23-05
    ];

    example-machine = {imports = [eu-central-1 t3a-small (ebs 40)];};
  };
}
