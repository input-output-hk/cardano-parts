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
#   flake.cardano-parts.cluster.group.<default|name>.groupName
#   flake.cardano-parts.cluster.group.<default|name>.groupPrefix
#   flake.cardano-parts.cluster.group.<default|name>.lib.cardanoLib
#   flake.cardano-parts.cluster.group.<default|name>.lib.topologyLib
#   flake.cardano-parts.cluster.group.<default|name>.meta.cardano-node-service
#   flake.cardano-parts.cluster.group.<default|name>.meta.domain
#   flake.cardano-parts.cluster.group.<default|name>.meta.environmentName
#   flake.cardano-parts.cluster.group.<default|name>.pkgs.cardano-cli
#   flake.cardano-parts.cluster.group.<default|name>.pkgs.cardano-node
#   flake.cardano-parts.cluster.group.<default|name>.pkgs.cardano-node-pkgs
#   flake.cardano-parts.cluster.group.<default|name>.pkgs.cardano-submit-api
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.cluster.<...>
flake @ {
  config,
  lib,
  withSystem,
  ...
}: let
  inherit (lib) mdDoc mkDefault mkOption types;
  inherit (types) addCheck anything attrsOf functionTo nullOr package port str submodule;

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
        description = mdDoc "Cardano-parts cluster options.";
        default = {};
      };
    };
  };

  clusterSubmodule = submodule {
    options = {
      infra = mkOption {
        type = infraSubmodule;
        description = mdDoc "Cardano-parts cluster infra submodule.";
        default = {};
      };

      group = mkOption {
        type = attrsOf groupSubmodule;
        description = mdDoc "Cardano-parts cluster group submodule.";
        default = {};
      };
    };
  };

  infraSubmodule = submodule {
    options = {
      aws = mkOption {
        type = awsSubmodule;
        description = mdDoc "Cardano-parts cluster infra aws submodule.";
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

  groupSubmodule = submodule ({name, ...}: {
    options = {
      meta = mkOption {
        type = metaSubmodule;
        description = mdDoc "Cardano-parts cluster group meta submodule.";
        default = {};
      };

      groupName = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group name.";
        default = name;
      };

      groupPrefix = mkOption {
        type = str;
        description = mdDoc ''
          Cardano-parts cluster group prefix.
          Machines belonging to this group will have Colmena names starting with this prefix;
        '';
        default = "";
      };

      pkgs = mkOption {
        type = pkgsSubmodule;
        description = mdDoc "Cardano-parts cluster group pkgs submodule.";
        default = {};
      };

      lib = mkOption {
        type = libSubmodule;
        description = mdDoc "Cardano-parts cluster group lib submodule.";
        default = {};
      };
    };
  });

  libSubmodule = submodule {
    options = {
      cardanoLib = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          Cardano-parts cluster group default cardanoLib.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardanoLib;
      };

      topologyLib = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc "Cardano-parts cluster group topologyLib.";
        default = cfg.lib.topologyLib;
      };
    };
  };

  metaSubmodule = submodule {
    options = {
      cardanoNodePort = mkOption {
        type = port;
        description = mdDoc "Cardano-parts cluster group cardanoNodePort.";
        default = 3001;
      };

      cardanoNodePrometheusExporterPort = mkOption {
        type = port;
        description = mdDoc "Cardano-parts cluster group cardanoNodePrometheusExporterPort.";
        default = 12798;
      };

      cardano-node-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-node-service import path string.";
        default = cfg.pkgs.special.cardano-node-service;
      };

      domain = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group domain.";
        default = cfgAws.domain;
      };

      environmentName = mkOption {
        type = nullOr str;
        description = mdDoc "Cardano-parts cluster group environmentName.";
        default = "custom";
      };
    };
  };

  pkgsSubmodule = submodule {
    options = {
      cardano-cli = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-cli package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-cli);
      };

      cardano-node = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-node package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node);
      };

      cardano-node-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          Cardano-parts cluster group default cardano-node-pkgs.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardano-node-pkgs;
      };

      cardano-submit-api = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-submit-api package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api);
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
