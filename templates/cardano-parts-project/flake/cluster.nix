{
  # -------------------------------------------------------------
  # For a new cluster, uncomment and update the following values:
  # -------------------------------------------------------------
  #
  # Define cluster-wide configuration.
  # This has to evaluate fast and is imported in various places.
  flake.cardano-parts.cluster = {
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
}
