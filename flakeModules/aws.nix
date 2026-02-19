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
  inherit (lib) foldl' mkDefault mkOption recursiveUpdate types;
  inherit (types) anything attrsOf submodule;

  cfg = config.flake.cardano-parts;
  cfgEc2 = cfg.aws.ec2;

  mainSubmodule = submodule {
    options = {
      aws = mkOption {
        type = awsSubmodule;
        description = "Cardano-parts aws options";
        default = {};
      };
    };
  };

  awsSubmodule = submodule {
    options = {
      ec2 = mkOption {
        type = ec2Submodule;
        description = "Cardano-parts aws ec2 options";
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
        defaultText = lib.literalExpression "builtins.fromJSON (builtins.readFile ./aws/ec2-spec.json)";
      };

      spec = mkOption {
        type = attrsOf anything;
        description = "The cardano-parts aws ec2 instance type spec reference.";
        defaultText = lib.literalExpression ''
          # Attrset of EC2 instance specs keyed by InstanceType, derived from rawSpec.
          # Each entry has: provider, nodeType, coreCount, cpuCount, memMiB, threadsPerCore.
        '';
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
