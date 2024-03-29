# flakeModule: inputs.cardano-parts.flakeModules.aws
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.aws.ec2.rawSpec
#   flake.cardano-parts.aws.ec2.spec
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.aws.<...>
{
  config,
  lib,
  ...
}: let
  inherit (lib) foldl' mdDoc mkDefault mkOption recursiveUpdate types;
  inherit (types) anything attrsOf submodule;

  cfg = config.flake.cardano-parts;
  cfgEc2 = cfg.aws.ec2;

  mainSubmodule = submodule {
    options = {
      aws = mkOption {
        type = awsSubmodule;
        description = mdDoc "Cardano-parts aws options";
        default = {};
      };
    };
  };

  awsSubmodule = submodule {
    options = {
      ec2 = mkOption {
        type = ec2Submodule;
        description = mdDoc "Cardano-parts aws ec2 options";
        default = {};
      };
    };
  };

  ec2Submodule = submodule {
    options = {
      rawSpec = mkOption {
        type = anything;
        description = mdDoc "The cardano-parts aws ec2 instance type raw spec reference.";
        default = builtins.fromJSON (builtins.readFile ./aws/ec2-spec.json);
      };

      spec = mkOption {
        type = attrsOf anything;
        description = mdDoc "The cardano-parts aws ec2 instance type spec reference.";
        default = foldl' (acc: spec:
          recursiveUpdate acc {
            ${spec.InstanceType} = {
              # The following are expected to be strings
              provider = "aws";
              nodeType = spec.InstanceType;

              # The following are expected to be ints
              # Total core count
              coreCount = spec.VCpuInfo.DefaultCores;

              # Total cpu count
              cpuCount = spec.VCpuInfo.DefaultVCpus;

              # Total memory in Mebibytes
              memMiB = spec.MemoryInfo.SizeInMiB;

              # Number of threads per core
              threadsPerCore = spec.VCpuInfo.DefaultThreadsPerCore;
            };
          }) {}
        cfgEc2.rawSpec.InstanceTypes;
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
