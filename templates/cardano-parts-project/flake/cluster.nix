{
  # -------------------------------------------------------------
  # For a new cluster, uncomment and update the following values:
  # -------------------------------------------------------------
  #
  # Define cluster-wide configuration.
  # This has to evaluate fast and is imported in various places.
  flake.cardano-parts.cluster = rec {
    infra.aws = {
      # orgId = "UPDATE_ME";
      # region = "eu-central-1";
      # profile = "UPDATE_ME";

      # A list of all regions in use, with a bool indicating inUse status.
      # Set a region to false to set its count to 0 in terraform.
      # After terraform applying once the line can be removed.
      #
      # regions = {
      #   eu-central-1 = true;
      # };

      # domain = "UPDATE_ME";

      # Preset defaults matched to default terraform rain infra; change if desired:
      # kms = "arn:aws:kms:${region}:${orgId}:alias/kmsKey";
      # bucketName = "${profile}-terraform";
    };

    infra.generic = {
      # Update basic info about the cluster here.
      # This will be used for generic resource tagging where possible.

      # organization = "iog";
      # tribe = "coretech";
      # function = "cardano-parts";
      # repo = "https://github.com/input-output-hk/UPDATE_ME";

      # By default abort and warn if the ip-module is missing:
      # abortOnMissingIpModule = true;
      # warnOnMissingIpModule = true;
    };

    # If using grafana cloud stack based monitoring.
    # infra.grafana.stackName = "UPDATE_ME";

    # For defining deployment groups with varying configuration.  Adjust as needed.
    groups = {
      preview1 = {
        groupPrefix = "preview1-";
        meta.environmentName = "preview";
        bookRelayMultivalueDns = "preview-node.${infra.aws.domain}";
        groupRelayMultivalueDns = "preview1-node.${infra.aws.domain}";
      };
    };
  };
}
