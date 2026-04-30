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
#   flake.cardano-parts.cluster.infra.monitoring.bucketLoki
#   flake.cardano-parts.cluster.infra.monitoring.bucketMimir
#   flake.cardano-parts.cluster.infra.monitoring.email
#   flake.cardano-parts.cluster.infra.monitoring.enable
#   flake.cardano-parts.cluster.infra.monitoring.hostname
#   flake.cardano-parts.cluster.infra.monitoring.oauth.google.allowedDomains
#   flake.cardano-parts.cluster.infra.monitoring.objectLockMode
#   flake.cardano-parts.cluster.infra.monitoring.provisionPath
#   flake.cardano-parts.cluster.infra.monitoring.retentionLogsDays
#   flake.cardano-parts.cluster.infra.monitoring.retentionMetricsDays
#   flake.cardano-parts.cluster.infra.monitoring.subdomain
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
  inherit (lib) mdDoc mkDefault mkOption types;
  inherit (types) addCheck anything attrsOf bool enum functionTo listOf nullOr oneOf package path port raw str submodule;

  cfg = config.flake.cardano-parts;
  cfgAws = cfg.cluster.infra.aws;
  cfgMon = cfg.cluster.infra.monitoring;

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

      monitoring = mkOption {
        type = monitoringSubmodule;
        description = mdDoc "Cardano-parts cluster infra in-cluster monitoring submodule.";
        default = {};
      };

      generic = mkOption {
        type = genericSubmodule;
        description = mdDoc "Cardano-parts cluster infra generic submodule.";
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

  monitoringSubmodule = submodule {
    options = {
      enable = mkOption {
        type = bool;
        description = mdDoc ''
          Whether to enable the in-cluster monitoring stack profile.

          When true, downstream:

          * Provisions an S3 bucket pair via opentofu for Mimir blocks and Loki chunks.
          * Provisions DNS for the monitoring node based on `hostname` and `infra.aws.domain`.
          * Auto-targets profile-grafana-alloy at the in-cluster monitoring node when no explicit remote write URL is configured.

          A Colmena machine matching `hostname` is expected to import the
          `nixosModules.profile-monitoring` module from cardano-parts.
        '';
        default = false;
      };

      hostname = mkOption {
        type = optionCheck "string" "infra.monitoring.hostname" "str";
        description = mdDoc ''
          The Colmena machine name expected to host the in-cluster monitoring stack.
          Used by opentofu to provision DNS, and by profile-grafana-alloy to
          derive the default remote write target.
        '';
        default = "monitoring";
      };

      subdomain = mkOption {
        type = optionCheck "string" "infra.monitoring.subdomain" "str";
        description = mdDoc ''
          The DNS label under `infra.aws.domain` at which Grafana is published.
          Defaults to `hostname` so the FQDN is `''${hostname}.''${infra.aws.domain}`.
        '';
        default = cfgMon.hostname;
      };

      bucketMimir = mkOption {
        type = optionCheck "string" "infra.monitoring.bucketMimir" "str";
        description = mdDoc ''
          The S3 bucket name used to store Mimir blocks and ruler state.
          Created by opentofu in the bootstrap workspace when monitoring is enabled.
        '';
        default = "${cfgAws.profile}-mimir";
      };

      bucketLoki = mkOption {
        type = optionCheck "string" "infra.monitoring.bucketLoki" "str";
        description = mdDoc ''
          The S3 bucket name used to store Loki chunks and indexes.
          Created by opentofu in the bootstrap workspace when monitoring is enabled.
        '';
        default = "${cfgAws.profile}-loki";
      };

      retentionMetricsDays = mkOption {
        type = optionCheck "int" "infra.monitoring.retentionMetricsDays" "int";
        description = mdDoc ''
          Mimir block retention in days. Drives both Mimir's compactor
          block retention and the S3 lifecycle expiration on the mimir
          bucket, so app-level and storage-level retention stay in lockstep.
        '';
        default = 365;
      };

      retentionLogsDays = mkOption {
        type = optionCheck "int" "infra.monitoring.retentionLogsDays" "int";
        description = mdDoc ''
          Loki retention in days. Drives both Loki's retention period and
          the S3 lifecycle expiration on the loki bucket.
        '';
        default = 180;
      };

      objectLockMode = mkOption {
        type = enum ["soft" "governance"];
        description = mdDoc ''
          S3 Object Lock policy applied to the mimir and loki buckets.
          Both options use GOVERNANCE-mode locks so a separately-permissioned
          ops role holding `s3:BypassGovernanceRetention` can break-glass for
          legitimate recovery (e.g. accidental secret leak); the EC2 role
          attached to monitoring nodes does not get that permission.

          * `"soft"` (default) — 1-day default retention. Stops a same-day
            compromise of the monitoring node from wiping fresh data.
            Compaction-driven source-block deletes succeed once objects
            age past the lock. Storage stays roughly 1× retention.

          * `"governance"` — default retention spans the full app
            retention window (`retentionMetricsDays` / `retentionLogsDays`).
            Compaction's source-block deletes fail until expiry, so storage
            roughly doubles during the retention window.

          Only the lock duration differs between modes. Switching modes
          after initial deploy applies to newly written objects only;
          existing locks are immutable.
        '';
        default = "soft";
      };

      email = mkOption {
        type = nullOr (optionCheck "string" "infra.monitoring.email" "str");
        description = mdDoc ''
          ACME contact email used by Caddy for the Grafana virtual host.

          Required when monitoring is enabled.
        '';
        default = null;
      };

      oauth = mkOption {
        type = monitoringOauthSubmodule;
        description = mdDoc ''
          Cardano-parts cluster infra monitoring oauth submodule.

          Currently only Google OAuth is exposed. Settings beyond what this
          submodule covers can be applied directly to
          `services.grafana.settings."auth.google"` on the monitoring machine.
        '';
        default = {};
      };

      provisionPath = mkOption {
        type = nullOr path;
        description = mdDoc ''
          Path to a directory containing monitoring assets to provision on
          the monitoring node.

          Currently the following layout is consumed:

          * `''${provisionPath}/dashboards/` — Grafana dashboard JSON files.
            All `*.json` files in this directory are picked up by Grafana
            file-based provisioning. Subdirectories are honored as folders.

          When null, no provisioning is configured; dashboards and alerts
          can still be edited in the Grafana UI but will not be persisted
          across redeploys.

          A typical downstream value is `''${self.outPath}/monitoring`.
        '';
        default = null;
      };
    };
  };

  monitoringOauthSubmodule = submodule {
    options = {
      google = mkOption {
        type = monitoringOauthGoogleSubmodule;
        description = mdDoc "Google OAuth submodule.";
        default = {};
      };
    };
  };

  monitoringOauthGoogleSubmodule = submodule {
    options = {
      allowedDomains = mkOption {
        type = listOf str;
        description = mdDoc ''
          Email domains permitted to log into Grafana via Google OAuth.

          Each entry is applied to both the `allowed_domains` and
          `hosted_domain` Grafana settings so the login is restricted to a
          single Google Workspace tenant.
        '';
        default = [];
        example = ["iohk.io"];
      };
    };
  };

  genericSubmodule = submodule {
    options = {
      abortOnMissingIpModule = mkOption {
        type = bool;
        description = mdDoc ''
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
        description = mdDoc ''
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
        description = mdDoc ''
          The cardano-parts cluster infra generic environment.

          This option is required by IOG IT/Finance.
        '';
        example = "testnets";
        default = null;
      };

      function = mkOption {
        type = optionCheck "string" "infra.generic.function" "str";
        description = mdDoc "The cardano-parts cluster infra generic function.";
        example = "cardano-parts";
        default = null;
      };

      organization = mkOption {
        type = optionCheck "string" "infra.generic.organization" "str";
        description = mdDoc "The cardano-parts cluster infra generic organization.";
        example = "iog";
        default = null;
      };

      owner = mkOption {
        type = optionCheck "string" "infra.generic.owner" "str";
        description = mdDoc ''
          The cardano-parts cluster infra generic owner.

          This option is required by IOG IT/Finance.
        '';
        example = "ioe";
        default = null;
      };

      project = mkOption {
        type = optionCheck "string" "infra.generic.project" "str";
        description = mdDoc ''
          The cardano-parts cluster infra generic project.

          This option is required by IOG IT/Finance.
        '';
        example = "cardano-playground";
        default = null;
      };

      repo = mkOption {
        type = optionCheck "string" "infra.generic.repo" "str";
        description = mdDoc "The cardano-parts cluster infra generic repo.";
        example = "https://github.com/input-output-hk/cardano-playground";
        default = null;
      };

      tribe = mkOption {
        type = optionCheck "string" "infra.generic.tribe" "str";
        description = mdDoc "The cardano-parts cluster infra generic tribe.";
        example = "coretech";
        default = null;
      };

      warnOnMissingIpModule = mkOption {
        type = bool;
        description = mdDoc ''
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
        description = mdDoc ''
          Cardano-parts cluster group(s) multivalue DNS.
          Machines belonging to this group and in the relay role have their IP A address added to this multivalue DNS record.
          This is intended to aggregate all group relays for a given environment to a single DNS for use as an upstream publicRoots.
        '';
        default = null;
      };

      generic = mkOption {
        type = groupGenericSubmodule;
        description = mdDoc "Cardano-parts cluster group generic submodule.";
        default = {};
      };

      groupBlockProducerSubstring = mkOption {
        type = str;
        description = mdDoc ''
          Cardano-parts cluster group block producer substring.
          Machines belonging to this group and in the block producer role will have Colmena names containing this substring.
        '';
        default = "bp-";
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

      meta = mkOption {
        type = groupMetaSubmodule;
        description = mdDoc "Cardano-parts cluster group meta submodule.";
        default = {};
      };

      pkgs = mkOption {
        type = groupPkgsSubmodule;
        description = mdDoc "Cardano-parts cluster group pkgs submodule.";
        default = {};
      };

      lib = mkOption {
        type = groupLibSubmodule;
        description = mdDoc "Cardano-parts cluster group lib submodule.";
        default = {};
      };
    };
  });

  groupGenericSubmodule = submodule {
    options = {
      abortOnMissingIpModule = mkOption {
        type = bool;
        description = mdDoc ''
          Cardano-parts cluster group option to abort on missing downstream provided "ip-module" nixosModule.
        '';
        default = cfg.cluster.infra.generic.abortOnMissingIpModule;
      };

      warnOnMissingIpModule = mkOption {
        type = bool;
        description = mdDoc ''
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
        description = mdDoc ''
          Cardano-parts cluster group default cardanoLib.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardanoLib;
      };

      opsLib = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc "Cardano-parts cluster group opsLib.";
        default = cfg.lib.opsLib;
      };

      topologyLib = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc "Cardano-parts cluster group topologyLib.";
        default = cfg.lib.topologyLib;
      };
    };
  };

  groupMetaSubmodule = submodule {
    options = {
      addressType = mkOption {
        type = enum ["fqdn" "namePrivateIpv4" "namePublicIpv4" "namePublicIpv6" "privateIpv4" "publicIpv4" "publicIpv6"];
        description = mdDoc "Cardano-parts cluster group default addressType for topologyLib mkProducer function.";
        default =
          if flake.config.flake.nixosModules ? ips
          then "namePublicIpv4"
          else "fqdn";
      };

      blockfrost-platform-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group blockfrost-platform-service import path string.";
        default = cfg.pkgs.special.blockfrost-platform-service;
      };

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

      cardano-db-sync-service-ng = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-db-sync-service-ng import path string.";
        default = cfg.pkgs.special.cardano-db-sync-service-ng;
      };

      cardano-faucet-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-faucet-service import path string.";
        default = cfg.pkgs.special.cardano-faucet-service;
      };

      cardano-metadata-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-metadata-service import path string.";
        default = cfg.pkgs.special.cardano-metadata-service;
      };

      cardano-node-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-node-service import path string.";
        default = cfg.pkgs.special.cardano-node-service;
      };

      cardano-node-service-ng = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-node-service-ng import path string.";
        default = cfg.pkgs.special.cardano-node-service-ng;
      };

      cardano-ogmios-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-ogmios-service import path string.";
        default = cfg.pkgs.special.cardano-ogmios-service;
      };

      cardano-smash-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-smash-service import path string.";
        default = cfg.pkgs.special.cardano-smash-service;
      };

      cardano-submit-api-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-submit-api-service import path string.";
        default = cfg.pkgs.special.cardano-submit-api-service;
      };

      cardano-submit-api-service-ng = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-submit-api-service-ng import path string.";
        default = cfg.pkgs.special.cardano-submit-api-service-ng;
      };

      cardano-tracer-service = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-tracer-service import path string.";
        default = cfg.pkgs.special.cardano-tracer-service;
      };

      cardano-tracer-service-ng = mkOption {
        type = str;
        description = mdDoc "Cardano-parts cluster group cardano-tracer-service-ng import path string.";
        default = cfg.pkgs.special.cardano-tracer-service-ng;
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

      hostsList = mkOption {
        type = oneOf [(enum ["all" "group"]) (listOf str)];
        description = mdDoc ''
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
        description = mdDoc "Cardano-parts cluster group default blockfrost-platform package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.blockfrost-platform);
      };

      blockperf = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default blockperf package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.blockperf);
      };

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

      cardano-metadata-pkgs = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          Cardano-parts cluster group default cardano-metadata-pkgs.

          The definition must be a function of system.
        '';
        default = cfg.pkgs.special.cardano-metadata-pkgs;
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

      cardano-ogmios = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-ogmios package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-ogmios);
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

      cardano-tracer = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default cardano-tracer package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-tracer);
      };

      mithril-client-cli = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default mithril-client-cli package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.mithril-client-cli);
      };

      mithril-signer = mkOption {
        type = functionTo package;
        description = mdDoc "Cardano-parts cluster group default mithril-signer package.";
        default = system: withSystem system ({config, ...}: config.cardano-parts.pkgs.mithril-signer);
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
