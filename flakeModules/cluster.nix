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
#   flake.cardano-parts.cluster.infra.grafana.stackName
#   flake.cardano-parts.cluster.groups.<default|name>.bookRelayMultivalueDns
#   flake.cardano-parts.cluster.groups.<default|name>.groupBlockProducerSubstring
#   flake.cardano-parts.cluster.groups.<default|name>.groupFlake
#   flake.cardano-parts.cluster.groups.<default|name>.groupName
#   flake.cardano-parts.cluster.groups.<default|name>.groupPrefix
#   flake.cardano-parts.cluster.groups.<default|name>.groupRelayMultivalueDns
#   flake.cardano-parts.cluster.groups.<default|name>.groupRelaySubstring
#   flake.cardano-parts.cluster.groups.<default|name>.lib.cardanoLib
#   flake.cardano-parts.cluster.groups.<default|name>.lib.topologyLib
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoDbSyncPrometheusExporterPort
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoNodePort
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoNodePrometheusExporterPort
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoSmashDelistedPools
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-db-sync-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-faucet-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-node-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-smash-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.domain
#   flake.cardano-parts.cluster.groups.<default|name>.meta.environmentName
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-cli
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-db-sync
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-db-sync-pkgs
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-db-tool
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-faucet
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-node
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-node-pkgs
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-smash
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-submit-api
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
  inherit (types) addCheck anything attrsOf functionTo listOf nullOr package port raw str submodule;

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

      groups = mkOption {
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

      grafana = mkOption {
        type = grafanaSubmodule;
        description = mdDoc "Cardano-parts cluster infra grafana submodule.";
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

  grafanaSubmodule = submodule {
    options = {
      stackName = mkOption {
        type = optionCheck "string" "infra.grafana.stackName" "str";
        description = mdDoc "The cardano-parts cluster infra grafana cloud stack name.";
        default = null;
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

      groupFlake = mkOption {
        type = attrsOf raw;
        description = mdDoc ''
          Cardano-parts cluster flake of the consuming repository.

          In certain cases, the cardano-parts flake will be used instead of the
          consuming repository's flake and this may not be desired behavior.

          Examples:

          * While importing nixosModules from cardano-parts, by default the `self`
          reference outPath will refer to cardano-parts directories, but for the
          secrets use case the desired path reference would be from groupFlake.

          * While overriding nixos config from cardano-parts nixosModules, any
          referenced perSystem or top level flake parts config options will originate
          from cardano-parts and not overrides set in the consuming repository.
          In this case, the desired withSystem or top level flake config context
          should also originate from groupFlake.
        '';
        default = flake;
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
          Machines belonging to this group will have Colmena names starting with this prefix.
        '';
        default = "";
      };

      bookRelayMultivalueDns = mkOption {
        type = nullOr str;
        description = mdDoc ''
          Cardano-parts cluster group(s) multivalue DNS.
          Machines belonging to this group and in the relay role have their IP A address added to this multivalue DNS record.
          This is intended to aggregate all group relays for a given environment to a single DNS for use as an upstream publicRoots.
        '';
        default = null;
      };

      groupRelayMultivalueDns = mkOption {
        type = nullOr str;
        description = mdDoc ''
          Cardano-parts cluster group multivalue DNS.
          Machines belonging to this group and in the relay role have their IP A address added to this multivalue DNS record.
          This is intended to aggregate all group relays for a given pool to a single DNS for use as registered pool relay DNS contact.
        '';
        default = null;
      };

      groupRelaySubstring = mkOption {
        type = str;
        description = mdDoc ''
          Cardano-parts cluster group relay substring.
          Machines belonging to this group and having Colmena names containing this substring,
          will be considered relays for the purposes of multivalue DNS generation via the
          bookRelayMultivalueDns and groupRelayMultivalueDns options.
        '';
        default = "rel-";
      };

      groupBlockProducerSubstring = mkOption {
        type = str;
        description = mdDoc ''
          Cardano-parts cluster group block producer substring.
          Machines belonging to this group and in the block producer role will have Colmena names containing this substring.
        '';
        default = "bp-";
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
      cardanoDbSyncPrometheusExporterPort = mkOption {
        type = port;
        description = mdDoc "Cardano-parts cluster group cardanoDbSyncPrometheusExporterPort.";
        default = 8080;
      };

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

      cardanoSmashDelistedPools = mkOption {
        type = listOf str;
        description = mdDoc "Cardano-parts cluster group cardano-smash delisted pools.";
        default = [];
      };

      cardano-db-sync-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-db-sync-service import path string.";
        default = cfg.pkgs.special.cardano-db-sync-service;
      };

      cardano-faucet-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-faucet-service import path string.";
        default = cfg.pkgs.special.cardano-faucet-service;
      };

      cardano-node-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-node-service import path string.";
        default = cfg.pkgs.special.cardano-node-service;
      };

      cardano-smash-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-smash-service import path string.";
        default = cfg.pkgs.special.cardano-smash-service;
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

      cardano-db-sync = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-db-sync package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-sync);
      };

      cardano-db-sync-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          Cardano-parts cluster group default cardano-db-sync-pkgs.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardano-db-sync-pkgs;
      };

      cardano-db-tool = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-db-tool package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-tool);
      };

      cardano-faucet = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-faucet package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-faucet);
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

      cardano-smash = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-smash package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-smash);
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
      groups.default = mkDefault {};
    };
  };
}
