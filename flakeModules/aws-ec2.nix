# flakeModule: inputs.cardano-parts.flakeModules.aws-ec2
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.aws-ec2.rawSpec
#   flake.cardano-parts.aws-ec2.spec
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.aws-ec2.<...>
{
  config,
  lib,
  ...
}: let
  inherit (lib) foldl' mdDoc mkDefault mkOption recursiveUpdate types;
  inherit (types) anything attrsOf submodule;

  cfg = config.flake.cardano-parts;
  cfgAwsEc2 = cfg.aws-ec2;

  mainSubmodule = submodule {
    options = {
      aws-ec2 = mkOption {
        type = awsEc2Submodule;
        description = mdDoc "Cardano-parts cluster options";
        default = {};
      };
    };
  };

  awsEc2Submodule = submodule {
    options = {
      rawSpec = mkOption {
        type = anything;
        description = mdDoc "The cardano-parts aws-ec2 instance type raw spec reference.";
        default = builtins.fromJSON (builtins.readFile ./aws-ec2.json);
      };

      spec = mkOption {
        type = attrsOf anything;
        description = mdDoc "The cardano-parts aws-ec2 instance type raw spec reference.";
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
        cfgAwsEc2.rawSpec.InstanceTypes;
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
    flake.cardano-parts = mkDefault {};
  };
}
