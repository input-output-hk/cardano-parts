# flakeModule: inputs.cardano-parts.flakeModules.cluster
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.cluster.infra.aws.bucketName
#   flake.cardano-parts.cluster.infra.aws.domain
#   flake.cardano-parts.cluster.infra.aws.kms
#   flake.cardano-parts.cluster.infra.aws.orgId
#   flake.cardano-parts.cluster.infra.aws.profile
#   flake.cardano-parts.cluster.infra.aws.region
#   flake.cardano-parts.cluster.infra.aws.regions
#   flake.cardano-parts.cluster.group.<default|name>.legacy.additionalPeers
#   flake.cardano-parts.cluster.group.<default|name>.legacy.cardanoNodePort
#   flake.cardano-parts.cluster.group.<default|name>.legacy.environmentConfig
#   flake.cardano-parts.cluster.group.<default|name>.legacy.explorerHostName
#   flake.cardano-parts.cluster.group.<default|name>.legacy.nbInstancesPerRelay
#   flake.cardano-parts.cluster.group.<default|name>.legacy.poolsExcludeList
#   flake.cardano-parts.cluster.group.<default|name>.legacy.relaysExcludeList
#   flake.cardano-parts.cluster.group.<default|name>.legacy.relayNodes
#   flake.cardano-parts.cluster.group.<default|name>.legacy.relaysNew
#   flake.cardano-parts.cluster.group.<default|name>.legacy.regions
#   flake.cardano-parts.cluster.group.<default|name>.legacy.regionsSubstitutes
#   flake.cardano-parts.cluster.group.<default|name>.legacy.topology
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.cluster.<...>
{
  config,
  lib,
  ...
}: let
  inherit (lib) mdDoc mkDefault mkOption types;
  inherit (types) addCheck anything attrsOf ints listOf port str submodule;

  cfg = config.flake.cardano-parts;
  cfgAws = cfg.cluster.infra.aws;

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
      infra = mkOption {
        type = infraSubmodule;
        description = mdDoc "Cardano-parts cluster infra submodule";
        default = {};
      };

      group = mkOption {
        type = attrsOf groupSubmodule;
        description = mdDoc "Cardano-parts cluster group submodule";
        default = {};
      };
    };
  };

  infraSubmodule = submodule {
    options = {
      aws = mkOption {
        type = awsSubmodule;
        description = mdDoc "Cardano-parts cluster infra aws submodule";
        default = {};
      };
    };
  };

  awsSubmodule = submodule {
    options = {
      orgId = mkOption {
        type = optionCheck "string" "infra.aws.orgId" "str";
        description = mdDoc "The cardano-parts cluster infra AWS organization ID.";
        default = null;
      };

      region = mkOption {
        type = optionCheck "string" "infra.aws.region" "str";
        description = mdDoc "The cardano-parts cluster infra AWS default region.";
        default = null;
      };

      regions = mkOption {
        type = optionCheck "set" "infra.aws.regions" "attrsOf bool";
        description = mdDoc ''
          The cardano-parts cluster infra AWS regions in use, including the default region.

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
        type = optionCheck "string" "infra.aws.kms" "str";
        description = mdDoc "The cardano-parts cluster infra AWS KMS ARN.";
        default = "arn:aws:kms:${cfgAws.region}:${cfgAws.orgId}:alias/kmsKey";
      };

      profile = mkOption {
        type = optionCheck "string" "infra.aws.profile" "str";
        description = mdDoc "The cardano-parts cluster AWS infra profile to use.";
        default = null;
      };

      domain = mkOption {
        type = optionCheck "string" "infra.aws.domain" "str";
        description = mdDoc "The cardano-parts cluster AWS infra domain to use.";
        default = null;
      };

      bucketName = mkOption {
        type = optionCheck "string" "infra.aws.bucketName" "str";
        description = mdDoc "The cardano-parts cluster infra AWS S3 bucket to use for Terraform state.";
        default = "${cfgAws.profile}-terraform";
      };
    };
  };

  groupSubmodule = submodule {
    options = {
      legacy = mkOption {
        type = legacySubmodule;
        description = mdDoc "Cardano-parts cluster group legacy submodule";
        default = {};
      };
    };
  };

  legacySubmodule = submodule {
    options = {
      additionalPeers = mkOption {
        type = listOf anything;
        description = mdDoc "The cardano-parts group additionalPeers definition for building group topology.";
        default = [];
      };

      cardanoNodePort = mkOption {
        type = port;
        description = mdDoc "The cardano-parts group cardanoNodePort definition for building group topology.";
        default = 3001;
      };

      environmentConfig = mkOption {
        type = attrsOf anything;
        description = mdDoc "The cardano-parts group environmentConfig definition for building group topology.";
        default = {};
      };

      explorerHostName = mkOption {
        type = str;
        description = mdDoc "The cardano-parts group environmentConfig definition for building group topology.";
        default = "https://explorer.cardano.org";
      };

      nbInstancesPerRelay = mkOption {
        type = ints.positive;
        description = mdDoc "The cardano-parts group nbInstancesPerRelay definition for building group topology.";
        default = 1;
      };

      poolsExcludeList = mkOption {
        type = listOf anything;
        description = mdDoc "The cardano-parts group poolsExcludeList definition for building group topology.";
        default = [];
      };

      relaysExcludeList = mkOption {
        type = listOf anything;
        description = mdDoc "The cardano-parts group relaysExcludeList definition for building group topology.";
        default = [];
      };

      relayNodes = mkOption {
        type = listOf anything;
        description = mdDoc "The cardano-parts group relayNodes definition for building group topology.";
        default = [];
      };

      relaysNew = mkOption {
        type = str;
        description = mdDoc "The cardano-parts group relaysNew definition for building group topology.";
        default = "";
      };

      regions = mkOption {
        type = attrsOf anything;
        description = mdDoc "The cardano-parts group regions definition for building group topology.";
        default = {};
      };

      regionsSubstitutes = mkOption {
        type = attrsOf anything;
        description = mdDoc "The cardano-parts group regionsSubstitutes definition for building group topology.";
        default = {};
      };

      topology = mkOption {
        type = attrsOf anything;
        description = mdDoc "The cardano-parts group topology definition for group topology.";
        default = {};
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
    flake.cardano-parts.cluster = {
      infra.aws = mkDefault {};
      group.default = mkDefault {};
    };
  };
}
