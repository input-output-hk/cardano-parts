{
  config,
  lib,
  ...
}: let
  inherit (lib) foldl' literalMD mkDefault mkOption recursiveUpdate types;
  inherit (types) anything attrsOf submodule;

  cfg = config.flake.cardano-parts;
  cfgEc2 = cfg.aws.ec2;

  mainSubmodule = submodule {
    options = {
      aws = mkOption {
        type = awsSubmodule;
        description = "Cardano-parts aws options.";
        default = {};
      };
    };
  };

  awsSubmodule = submodule {
    options = {
      ec2 = mkOption {
        type = ec2Submodule;
        description = "Cardano-parts aws ec2 options.";
        default = {};
      };
    };
  };

  ec2Submodule = submodule {
    options = {
      rawSpec = mkOption {
        type = anything;
        description = "The cardano-parts aws ec2 instance type raw spec reference.";
        default = builtins.fromJSON (builtins.readFile ./aws/ec2-spec.json);
        defaultText = literalMD "`builtins.fromJSON (builtins.readFile ./aws/ec2-spec.json)`";
      };

      spec = mkOption {
        type = attrsOf anything;
        description = "The cardano-parts aws ec2 instance type spec reference.";
        default = foldl' (acc: spec:
          recursiveUpdate acc {
            ${spec.InstanceType} = {
              provider = "aws";
              coreCount = spec.VCpuInfo.DefaultCores;
              cpuCount = spec.VCpuInfo.DefaultVCpus;
              nodeType = spec.InstanceType;
              memMiB = spec.MemoryInfo.SizeInMiB;
              threadsPerCore = spec.VCpuInfo.DefaultThreadsPerCore;
            };
          }) {}
        cfgEc2.rawSpec.InstanceTypes;
        defaultText = literalMD ''
          ```
          foldl' (acc: spec:
            recursiveUpdate acc {
              ''${spec.InstanceType} = {
                provider = "aws";
                coreCount = spec.VCpuInfo.DefaultCores;
                cpuCount = spec.VCpuInfo.DefaultVCpus;
                nodeType = spec.InstanceType;
                memMiB = spec.MemoryInfo.SizeInMiB;
                threadsPerCore = spec.VCpuInfo.DefaultThreadsPerCore;
              };
            }) {}
          ```
        '';
      };
    };
  };
in {
  options = {
    # Top level option definition
    flake.cardano-parts = mkOption {
      type = mainSubmodule;
    };
  };

  config = {
    # Top level config definition
    flake.cardano-parts = mkDefault {};
  };
}
