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
#   flake.cardano-parts.cluster.infra.generic.abortOnMissingIpModule
#   flake.cardano-parts.cluster.infra.generic.costCenter
#   flake.cardano-parts.cluster.infra.generic.environment
#   flake.cardano-parts.cluster.infra.generic.function
#   flake.cardano-parts.cluster.infra.generic.organization
#   flake.cardano-parts.cluster.infra.generic.owner
#   flake.cardano-parts.cluster.infra.generic.project
#   flake.cardano-parts.cluster.infra.generic.repo
#   flake.cardano-parts.cluster.infra.generic.tribe
#   flake.cardano-parts.cluster.infra.generic.warnOnMissingIpModule
#   flake.cardano-parts.cluster.infra.grafana.stackName
#   flake.cardano-parts.cluster.groups.<default|name>.bookRelayMultivalueDns
#   flake.cardano-parts.cluster.groups.<default|name>.generic.abortOnMissingIpModule
#   flake.cardano-parts.cluster.groups.<default|name>.generic.warnOnMissingIpModule
#   flake.cardano-parts.cluster.groups.<default|name>.groupBlockProducerSubstring
#   flake.cardano-parts.cluster.groups.<default|name>.groupFlake
#   flake.cardano-parts.cluster.groups.<default|name>.groupName
#   flake.cardano-parts.cluster.groups.<default|name>.groupPrefix
#   flake.cardano-parts.cluster.groups.<default|name>.groupRelayMultivalueDns
#   flake.cardano-parts.cluster.groups.<default|name>.groupRelaySubstring
#   flake.cardano-parts.cluster.groups.<default|name>.lib.cardanoLib
#   flake.cardano-parts.cluster.groups.<default|name>.lib.opsLib
#   flake.cardano-parts.cluster.groups.<default|name>.lib.topologyLib
#   flake.cardano-parts.cluster.groups.<default|name>.meta.addressType
#   flake.cardano-parts.cluster.groups.<default|name>.meta.blockfrost-platform-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoDbSyncPrometheusExporterPort
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoNodePort
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoNodePrometheusExporterPort
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardanoSmashDelistedPools
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-db-sync-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-db-sync-service-ng
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-faucet-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-metadata-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-node-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-node-service-ng
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-ogmios-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-smash-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-submit-api-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-submit-api-service-ng
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-tracer-service
#   flake.cardano-parts.cluster.groups.<default|name>.meta.cardano-tracer-service-ng
#   flake.cardano-parts.cluster.groups.<default|name>.meta.domain
#   flake.cardano-parts.cluster.groups.<default|name>.meta.environmentName
#   flake.cardano-parts.cluster.groups.<default|name>.meta.hostsList
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.blockperf
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.blockfrost-platform
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-cli
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-db-sync
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-db-sync-pkgs
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-db-tool
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-faucet
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-metadata-pkgs
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-node
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-node-pkgs
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-ogmios
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-smash
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-submit-api
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.cardano-tracer
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.mithril-client-cli
#   flake.cardano-parts.cluster.groups.<default|name>.pkgs.mithril-signer
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.cluster.<...>
flake @ {
  config,
  lib,
  withSystem,
  ...
}: let
  inherit (lib) mkDefault mkOption types;
  inherit (types) addCheck anything attrsOf bool enum functionTo listOf nullOr oneOf package port raw str submodule;

  cfg = config.flake.cardano-parts;
  cfgAws = cfg.cluster.infra.aws;

  # TODO: improved function to do real type checking while still providing a useful message
  # null is allowed since many of these options have null defaults and are set by the user.
  optionCheck = type: optionName: typeName:
    addCheck anything (f:
      if f == null || builtins.typeOf f == type
      then true
      else builtins.abort "flake.cardano-parts.cluster.${optionName} must be a declared type of: ${typeName}");

  mainSubmodule = submodule {
    options = {
      cluster = mkOption {
        type = clusterSubmodule;
        description = "Cardano-parts cluster options.";
        default = {};
      };
    };
  };

  clusterSubmodule = submodule {
    options = {
      infra = mkOption {
        type = infraSubmodule;
        description = "Cardano-parts cluster infra submodule.";
        default = {};
      };

      groups = mkOption {
        type = attrsOf groupSubmodule;
        description = "Cardano-parts cluster group submodule.";
        default = {};
      };
    };
  };

  infraSubmodule = submodule {
    options = {
      aws = mkOption {
        type = awsSubmodule;
        description = "Cardano-parts cluster infra aws submodule.";
        default = {};
      };

      grafana = mkOption {
        type = grafanaSubmodule;
        description = "Cardano-parts cluster infra grafana submodule.";
        default = {};
      };

      generic = mkOption {
        type = genericSubmodule;
        description = "Cardano-parts cluster infra generic submodule.";
        default = {};
      };
    };
  };

  awsSubmodule = submodule {
    options = {
      orgId = mkOption {
        type = optionCheck "string" "infra.aws.orgId" "str";
        description = "The cardano-parts cluster infra AWS organization ID.";
        default = null;
      };

      region = mkOption {
        type = optionCheck "string" "infra.aws.region" "str";
        description = "The cardano-parts cluster infra AWS default region.";
        default = null;
      };

      regions = mkOption {
        type = optionCheck "set" "infra.aws.regions" "attrsOf bool";
        description = ''
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
        description = "The cardano-parts cluster infra AWS KMS ARN.";
        default =
          if cfgAws.region != null && cfgAws.orgId != null
          then "arn:aws:kms:${cfgAws.region}:${cfgAws.orgId}:alias/kmsKey"
          else null;
        defaultText = lib.literalMD "*see source*";
      };

      profile = mkOption {
        type = optionCheck "string" "infra.aws.profile" "str";
        description = "The cardano-parts cluster AWS infra profile to use.";
        default = null;
      };

      domain = mkOption {
        type = optionCheck "string" "infra.aws.domain" "str";
        description = "The cardano-parts cluster AWS infra domain to use.";
        default = null;
      };

      bucketName = mkOption {
        type = optionCheck "string" "infra.aws.bucketName" "str";
        description = "The cardano-parts cluster infra AWS S3 bucket to use for Terraform state.";
        default =
          if cfgAws.profile != null
          then "${cfgAws.profile}-terraform"
          else null;
        defaultText = lib.literalMD "*see source*";
      };
    };
  };

  grafanaSubmodule = submodule {
    options = {
      stackName = mkOption {
        type = optionCheck "string" "infra.grafana.stackName" "str";
        description = "The cardano-parts cluster infra grafana cloud stack name.";
        default = null;
      };
    };
  };

  genericSubmodule = submodule {
    options = {
      abortOnMissingIpModule = mkOption {
        type = bool;
        description = ''
          The cardano-parts cluster infra generic option to abort if the
          downstream provided "ip-module" nixosModule is missing.

          Most clusters will utilize the ip-module and if missing
          may cause builds or deployed software and services to break.

          In some special cases use of ip-module may not be desired
          and aborts can be disabled by setting this option false.

          The ip-module is generated by the downstream repo with a
          `just update-ips` recipe.  See the template file for an example:

            templates/cardano-parts-project/Justfile
        '';
        default = true;
      };

      costCenter = mkOption {
        type = optionCheck "string" "infra.generic.costCenter" "str";
        description = ''
          The cardano-parts cluster infra generic costCenter.

          By default, the costCenter string for tagging cloud resources is
          treated as a secret and must be added to the
          secrets/tf/cluster.tfvars file.

          The string declared for this option should be the name of the secret
          var stored in the cluster.tfvars file.

          This option is required by IOG IT/Finance.
        '';
        example = "tag_costCenter";
        default = null;
      };

      environment = mkOption {
        type = optionCheck "string" "infra.generic.environment" "str";
        description = ''
          The cardano-parts cluster infra generic environment.

          This option is required by IOG IT/Finance.
        '';
        example = "testnets";
        default = null;
      };

      function = mkOption {
        type = optionCheck "string" "infra.generic.function" "str";
        description = "The cardano-parts cluster infra generic function.";
        example = "cardano-parts";
        default = null;
      };

      organization = mkOption {
        type = optionCheck "string" "infra.generic.organization" "str";
        description = "The cardano-parts cluster infra generic organization.";
        example = "iog";
        default = null;
      };

      owner = mkOption {
        type = optionCheck "string" "infra.generic.owner" "str";
        description = ''
          The cardano-parts cluster infra generic owner.

          This option is required by IOG IT/Finance.
        '';
        example = "ioe";
        default = null;
      };

      project = mkOption {
        type = optionCheck "string" "infra.generic.project" "str";
        description = ''
          The cardano-parts cluster infra generic project.

          This option is required by IOG IT/Finance.
        '';
        example = "cardano-playground";
        default = null;
      };

      repo = mkOption {
        type = optionCheck "string" "infra.generic.repo" "str";
        description = "The cardano-parts cluster infra generic repo.";
        example = "https://github.com/input-output-hk/cardano-playground";
        default = null;
      };

      tribe = mkOption {
        type = optionCheck "string" "infra.generic.tribe" "str";
        description = "The cardano-parts cluster infra generic tribe.";
        example = "coretech";
        default = null;
      };

      warnOnMissingIpModule = mkOption {
        type = bool;
        description = ''
          The cardano-parts cluster infra generic option to warn if the
          downstream provided "ip-module" nixosModule is missing.

          Most clusters will utilize the ip-module and if missing
          may cause builds or deployed software and services to break.

          In some special cases use of ip-module may not be desired
          and warnings can be disabled by setting this option false.

          The ip-module is generated by the downstream repo with a
          `just update-ips` recipe.  See the template file for an example:

            templates/cardano-parts-project/Justfile
        '';
        default = true;
      };
    };
  };

  groupSubmodule = submodule ({name, ...}: {
    options = {
      bookRelayMultivalueDns = mkOption {
        type = nullOr str;
        description = ''
          Cardano-parts cluster group(s) multivalue DNS.
          Machines belonging to this group and in the relay role have their IP A address added to this multivalue DNS record.
          This is intended to aggregate all group relays for a given environment to a single DNS for use as an upstream publicRoots.
        '';
        default = null;
      };

      generic = mkOption {
        type = groupGenericSubmodule;
        description = "Cardano-parts cluster group generic submodule.";
        default = {};
      };

      groupBlockProducerSubstring = mkOption {
        type = str;
        description = ''
          Cardano-parts cluster group block producer substring.
          Machines belonging to this group and in the block producer role will have Colmena names containing this substring.
        '';
        default = "bp-";
      };

      groupFlake = mkOption {
        type = attrsOf raw;
        description = ''
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
        defaultText = lib.literalMD "*see source*";
      };

      groupName = mkOption {
        type = str;
        description = "Cardano-parts cluster group name.";
        default = name;
      };

      groupPrefix = mkOption {
        type = str;
        description = ''
          Cardano-parts cluster group prefix.
          Machines belonging to this group will have Colmena names starting with this prefix.
        '';
        default = "";
      };

      groupRelayMultivalueDns = mkOption {
        type = nullOr str;
        description = ''
          Cardano-parts cluster group multivalue DNS.
          Machines belonging to this group and in the relay role have their IP A address added to this multivalue DNS record.
          This is intended to aggregate all group relays for a given pool to a single DNS for use as registered pool relay DNS contact.
        '';
        default = null;
      };

      groupRelaySubstring = mkOption {
        type = str;
        description = ''
          Cardano-parts cluster group relay substring.
          Machines belonging to this group and having Colmena names containing this substring,
          will be considered relays for the purposes of multivalue DNS generation via the
          bookRelayMultivalueDns and groupRelayMultivalueDns options.
        '';
        default = "rel-";
      };

      meta = mkOption {
        type = groupMetaSubmodule;
        description = "Cardano-parts cluster group meta submodule.";
        default = {};
      };

      pkgs = mkOption {
        type = groupPkgsSubmodule;
        description = "Cardano-parts cluster group pkgs submodule.";
        default = {};
      };

      lib = mkOption {
        type = groupLibSubmodule;
        description = "Cardano-parts cluster group lib submodule.";
        default = {};
      };
    };
  });

  groupGenericSubmodule = submodule {
    options = {
      abortOnMissingIpModule = mkOption {
        type = bool;
        description = ''
          Cardano-parts cluster group option to abort on missing downstream provided "ip-module" nixosModule.
        '';
        default = cfg.cluster.infra.generic.abortOnMissingIpModule;
      };

      warnOnMissingIpModule = mkOption {
        type = bool;
        description = ''
          Cardano-parts cluster group option to warn on missing downstream provided "ip-module" nixosModule.
        '';
        default = cfg.cluster.infra.generic.warnOnMissingIpModule;
      };
    };
  };

  groupLibSubmodule = submodule {
    options = {
      cardanoLib = mkOption {
        type = functionTo (attrsOf anything);
        description = ''
          Cardano-parts cluster group default cardanoLib.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardanoLib;
        defaultText = lib.literalMD "*see source*";
      };

      opsLib = mkOption {
        type = functionTo (attrsOf anything);
        description = "Cardano-parts cluster group opsLib.";
        default = cfg.lib.opsLib;
        defaultText = lib.literalMD "*see source*";
      };

      topologyLib = mkOption {
        type = functionTo (attrsOf anything);
        description = "Cardano-parts cluster group topologyLib.";
        default = cfg.lib.topologyLib;
        defaultText = lib.literalMD "*see source*";
      };
    };
  };

  groupMetaSubmodule = submodule {
    options = {
      addressType = mkOption {
        type = enum ["fqdn" "namePrivateIpv4" "namePublicIpv4" "namePublicIpv6" "privateIpv4" "publicIpv4" "publicIpv6"];
        description = "Cardano-parts cluster group default addressType for topologyLib mkProducer function.";
        default =
          if flake.config.flake.nixosModules ? ips
          then "namePublicIpv4"
          else "fqdn";
      };

      blockfrost-platform-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group blockfrost-platform-service import path string.";
        default = cfg.pkgs.special.blockfrost-platform-service;
      };

      cardanoDbSyncPrometheusExporterPort = mkOption {
        type = port;
        description = "Cardano-parts cluster group cardanoDbSyncPrometheusExporterPort.";
        default = 8080;
      };

      cardanoNodePort = mkOption {
        type = port;
        description = "Cardano-parts cluster group cardanoNodePort.";
        default = 3001;
      };

      cardanoNodePrometheusExporterPort = mkOption {
        type = port;
        description = "Cardano-parts cluster group cardanoNodePrometheusExporterPort.";
        default = 12798;
      };

      cardanoSmashDelistedPools = mkOption {
        type = listOf str;
        description = "Cardano-parts cluster group cardano-smash delisted pools.";
        default = [];
      };

      cardano-db-sync-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-db-sync-service import path string.";
        default = cfg.pkgs.special.cardano-db-sync-service;
      };

      cardano-db-sync-service-ng = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-db-sync-service-ng import path string.";
        default = cfg.pkgs.special.cardano-db-sync-service-ng;
      };

      cardano-faucet-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-faucet-service import path string.";
        default = cfg.pkgs.special.cardano-faucet-service;
      };

      cardano-metadata-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-metadata-service import path string.";
        default = cfg.pkgs.special.cardano-metadata-service;
      };

      cardano-node-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-node-service import path string.";
        default = cfg.pkgs.special.cardano-node-service;
      };

      cardano-node-service-ng = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-node-service-ng import path string.";
        default = cfg.pkgs.special.cardano-node-service-ng;
      };

      cardano-ogmios-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-ogmios-service import path string.";
        default = cfg.pkgs.special.cardano-ogmios-service;
      };

      cardano-smash-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-smash-service import path string.";
        default = cfg.pkgs.special.cardano-smash-service;
      };

      cardano-submit-api-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-submit-api-service import path string.";
        default = cfg.pkgs.special.cardano-submit-api-service;
      };

      cardano-submit-api-service-ng = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-submit-api-service-ng import path string.";
        default = cfg.pkgs.special.cardano-submit-api-service-ng;
      };

      cardano-tracer-service = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-tracer-service import path string.";
        default = cfg.pkgs.special.cardano-tracer-service;
      };

      cardano-tracer-service-ng = mkOption {
        type = str;
        description = "Cardano-parts cluster group cardano-tracer-service-ng import path string.";
        default = cfg.pkgs.special.cardano-tracer-service-ng;
      };

      domain = mkOption {
        type = nullOr str;
        description = "Cardano-parts cluster group domain.";
        default = cfgAws.domain;
      };

      environmentName = mkOption {
        type = nullOr str;
        description = "Cardano-parts cluster group environmentName.";
        default = "custom";
      };

      hostsList = mkOption {
        type = oneOf [(enum ["all" "group"]) (listOf str)];
        description = ''
          A list of Colmena machine names for which /etc/hosts will be configured for if
          nixosModule.ip-module is available in the downstream repo and profile-cardano-parts
          nixosModule is imported.

          If instead of a list, this option is configured with a string of "all", all
          Colmena machine names in the cluster will be used for the /etc/hosts file.

          If configured with a string of "group" then all Colmena machine names in the
          same group will be used for the /etc/hosts file.
        '';
        default = "group";
      };
    };
  };

  groupPkgsSubmodule = submodule {
    options = {
      blockfrost-platform = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default blockfrost-platform package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.blockfrost-platform);
        defaultText = lib.literalMD "*see source*";
      };

      blockperf = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default blockperf package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.blockperf);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-cli = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-cli package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-cli);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-db-sync = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-db-sync package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-sync);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-db-sync-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = ''
          Cardano-parts cluster group default cardano-db-sync-pkgs.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardano-db-sync-pkgs;
        defaultText = lib.literalMD "*see source*";
      };

      cardano-db-tool = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-db-tool package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-tool);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-faucet = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-faucet package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-faucet);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-metadata-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = ''
          Cardano-parts cluster group default cardano-metadata-pkgs.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardano-metadata-pkgs;
        defaultText = lib.literalMD "*see source*";
      };

      cardano-node = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-node package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-node-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = ''
          Cardano-parts cluster group default cardano-node-pkgs.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardano-node-pkgs;
        defaultText = lib.literalMD "*see source*";
      };

      cardano-ogmios = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-ogmios package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-ogmios);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-smash = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-smash package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-smash);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-submit-api = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-submit-api package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api);
        defaultText = lib.literalMD "*see source*";
      };

      cardano-tracer = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default cardano-tracer package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-tracer);
        defaultText = lib.literalMD "*see source*";
      };

      mithril-client-cli = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default mithril-client-cli package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.mithril-client-cli);
        defaultText = lib.literalMD "*see source*";
      };

      mithril-signer = mkOption {
        type = functionTo package;
        description = "Cardano-parts cluster group default mithril-signer package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.mithril-signer);
        defaultText = lib.literalMD "*see source*";
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
      infra.generic = mkDefault {};
      groups.default = mkDefault {};
    };
  };
}
