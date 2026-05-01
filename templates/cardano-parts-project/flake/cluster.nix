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

      # organization = "ioe";
      # tribe = "coretech";
      # function = "cardano-parts";
      # repo = "https://github.com/input-output-hk/UPDATE_ME";

      # owner = "ioe";
      # environment = "testnets";
      # project = "cardano-playground";

      # This is the tf var secrets name located in secrets/tf/cluster.tfvars
      # costCenter = "tag_costCenter";

      # By default abort and warn if the ip-module is missing:
      # abortOnMissingIpModule = true;
      # warnOnMissingIpModule = true;
    };

    # If using grafana cloud stack based monitoring.
    # infra.grafana.stackName = "UPDATE_ME";

    # Optional: in-cluster monitoring stack (Grafana + Mimir + Loki + Caddy).
    # Deploys a single monitoring machine that consumes metrics and logs
    # from the rest of the cluster via profile-grafana-alloy.
    #
    # When enabled:
    #   * opentofu/bootstrap creates `${profile}-mimir` and `${profile}-loki`
    #     S3 buckets with Object Lock + lifecycle. The EC2 role gets
    #     least-privilege data-plane access (no bucket-management actions,
    #     no governance bypass).
    #   * profile-grafana-alloy auto-targets the in-cluster monitoring node;
    #     `grafana-alloy-{metrics,loki}-url` sops secrets become optional.
    #   * A Colmena machine matching `infra.monitoring.hostname` (default
    #     "monitoring") must be declared with `profile-monitoring` imported
    #     and `enableDns = true` so the DNS A record is created at
    #     `${subdomain}.${infra.aws.domain}`.
    #
    # infra.monitoring = {
    #   enable = true;
    #   email = "devops+monitoring@UPDATE_ME";
    #   oauth.google.allowedDomain = "UPDATE_ME";
    #
    #   # Reuse the existing tofu grafana directory so dashboards, alerts,
    #   # and recording rules feed both the in-cluster Mimir/Grafana and
    #   # any external tofu-driven cardano-monitoring workspace.
    #   provisionPath = ./opentofu/grafana;
    #
    #   # Storage retention. Drives both app-level retention and S3
    #   # lifecycle expiration so they cannot drift.
    #   # retentionMetricsDays = 365;
    #   # retentionLogsDays = 180;
    #
    #   # S3 Object Lock policy. "soft" (default) gives a 1-day immutability
    #   # window — cheap, blocks same-day mass-delete from a compromised
    #   # node. "governance" locks for the full retention window — roughly
    #   # doubles storage cost but a compromised node cannot delete pre-
    #   # expiry. Both modes are GOVERNANCE-mode; a separately-permissioned
    #   # operator role with `s3:BypassGovernanceRetention` can break-glass.
    #   # objectLockMode = "soft";
    # };

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
