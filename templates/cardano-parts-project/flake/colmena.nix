{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (config.flake) nixosModules;
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
    meta.nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
    };

    defaults.imports = [
      inputs.cardano-parts.nixosModules.aws-ec2
      inputs.cardano-parts.nixosModules.common
      nixosModules.common
      nixos-23-05
    ];

    example-machine = {imports = [eu-central-1 t3a-small (ebs 40)];};
  };
}
