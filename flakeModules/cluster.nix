{
  config,
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mdDoc mkDefault mkOption types;
  inherit (types) attrsOf bool str submodule;

  cfg = config.flake.cardano-parts;
  cfgCluster = cfg.cluster;

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
        type = str;
        description = mdDoc "The cardano-parts cluster AWS organization ID.";
        default = null;
      };

      region = mkOption {
        type = str;
        description = mdDoc "The cardano-parts cluster AWS default region.";
        default = null;
      };

      regions = mkOption {
        type = attrsOf bool;
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
        type = str;
        description = mdDoc "The cardano-parts cluster AWS KMS ARN.";
        default = "arn:aws:kms:${cfgCluster.region}:${cfgCluster.orgId}:alias/kmsKey";
      };

      profile = mkOption {
        type = str;
        description = mdDoc "The cardano-parts cluster AWS profile to use.";
        default = null;
      };

      domain = mkOption {
        type = str;
        description = mdDoc "The cardano-parts cluster AWS domain to use.";
        default = null;
      };

      bucketName = mkOption {
        type = str;
        description = mdDoc "The cardano-parts cluster AWS S3 bucket to use for Terraform state.";
        default = "${cfgCluster.profile}-terraform";
      };
    };
  };
in {
  options = {
    _file = ./cluster.nix;

    # Top level option definition
    flake.cardano-parts = mkOption {
      type = mainSubmodule;
    };
  };

  config = {
    flake.cardano-parts = mkDefault {};
  };
}
