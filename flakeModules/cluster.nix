# flakeModule: inputs.cardano-parts.flakeModules.cluster
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.cluster.bucketName
#   flake.cardano-parts.cluster.domain
#   flake.cardano-parts.cluster.kms
#   flake.cardano-parts.cluster.orgId
#   flake.cardano-parts.cluster.profile
#   flake.cardano-parts.cluster.region
#   flake.cardano-parts.cluster.regions
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.cluster.<...>
{
  config,
  lib,
  ...
}: let
  inherit (lib) mdDoc mkDefault mkOption types;
  inherit (types) addCheck anything submodule;

  cfg = config.flake.cardano-parts;
  cfgCluster = cfg.cluster;

  # TODO: improved function to do real type checking while still providing a useful message
  optionCheck = type: optionName: typeName:
    addCheck anything (f:
      if builtins.typeOf f == type
      then true
      else builtins.abort "flake.cardano-parts.cluster.${optionName} must be a declared type of: ${typeName}");

  mainSubmodule = submodule {
    options = {
      cluster = mkOption {
        type = clusterSubmodule;
        description = mdDoc "Cardano-parts cluster options";
        default = {};
      };
    };
  };

  clusterSubmodule = submodule {
    options = {
      orgId = mkOption {
        type = optionCheck "string" "orgId" "str";
        description = mdDoc "The cardano-parts cluster AWS organization ID.";
        default = null;
      };

      region = mkOption {
        type = optionCheck "string" "region" "str";
        description = mdDoc "The cardano-parts cluster AWS default region.";
        default = null;
      };

      regions = mkOption {
        type = optionCheck "set" "regions" "attrsOf bool";
        description = mdDoc ''
          The cardano-parts cluster AWS regions in use, including the default region.

          Regions are given as attrNames with a value of bool.
          The bool value allows terraform to determine if region resources should be purged.
        '';
        example = {
          eu-central-1 = true;
          us-east-2 = true;
        };
        default = null;
      };

      kms = mkOption {
        type = optionCheck "string" "kms" "str";
        description = mdDoc "The cardano-parts cluster AWS KMS ARN.";
        default = "arn:aws:kms:${cfgCluster.region}:${cfgCluster.orgId}:alias/kmsKey";
      };

      profile = mkOption {
        type = optionCheck "string" "profile" "str";
        description = mdDoc "The cardano-parts cluster AWS profile to use.";
        default = null;
      };

      domain = mkOption {
        type = optionCheck "string" "domain" "str";
        description = mdDoc "The cardano-parts cluster AWS domain to use.";
        default = null;
      };

      bucketName = mkOption {
        type = optionCheck "string" "bucketName" "str";
        description = mdDoc "The cardano-parts cluster AWS S3 bucket to use for Terraform state.";
        default = "${cfgCluster.profile}-terraform";
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
