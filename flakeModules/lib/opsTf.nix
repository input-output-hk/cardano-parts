lib:
# Argument `lib` is provided by the lib flakeModule opsTf option default:
#   flake.cardano-parts.lib.opsTf
#
# Pure helpers for opentofu (terranix) workspaces. Functions here return
# attrset fragments suitable for merging into a workspace's `imports`
# list — they do not depend on `pkgs`, so they can be called from any
# workspace regardless of how that workspace acquires nixpkgs.
with lib; rec {
  # Translate a region like `eu-central-1` into `eu_central_1` for use
  # in the `aws.<region>` provider alias names that downstream tofu
  # workspaces declare.
  dashToSnake = replaceStrings ["-"] ["_"];

  # Provider alias for an AWS region. Workspaces declare one provider
  # per active region, so resources targeting that region must use the
  # matching alias.
  awsProviderFor = region: "aws.${dashToSnake region}";

  # Bucket policy statement that denies any non-TLS request. Apply to
  # every bucket the workspace creates so requests over plain HTTP are
  # rejected at the bucket level (defence in depth on top of the
  # provider's TLS-enforced endpoint).
  bucketPolicyStatementSecureTransport = bucketArn: {
    sid = "RestrictToTLSRequestsOnly";
    effect = "Deny";
    actions = ["s3:*"];
    resources = [
      bucketArn
      "${bucketArn}/*"
    ];
    condition = {
      test = "Bool";
      variable = "aws:SecureTransport";
      values = ["false"];
    };
    principals = {
      type = "*";
      identifiers = ["*"];
    };
  };

  # Mimir + Loki S3 bucket resources for the in-cluster monitoring
  # stack. Returns a workspace fragment ({data, resource}) suitable for
  # merging via `imports = [... (mkMonitoringBucketResources {...})]`.
  #
  # Object Lock + lifecycle pin app-level and storage-level retention
  # together: lifecycle expires objects on day N (matching the app's
  # configured retention), while Object Lock prevents the EC2 role
  # from deleting objects pre-expiry. Both modes use GOVERNANCE locks
  # so a separately-permissioned ops role with
  # s3:BypassGovernanceRetention can break-glass; the EC2 role itself
  # is not granted that permission.
  mkMonitoringBucketResources = {
    monitoring,
    awsRegion,
    awsOrgId,
  }: let
    inherit (monitoring) bucketLoki bucketMimir objectLockMode retentionLogsDays retentionMetricsDays;

    # "soft" → minimum 1 day (AWS API floor). Survives same-day
    # compromise; compaction-driven deletes succeed once objects age
    # past the lock.
    # "governance" → full app retention. Compaction sources cannot be
    # deleted before expiry, so storage roughly doubles during the
    # retention window.
    lockDaysFor = retentionDays:
      if objectLockMode == "governance"
      then retentionDays
      else 1;

    bucketSpecs = {
      mimir = {
        bucket = bucketMimir;
        retentionDays = retentionMetricsDays;
        lockDays = lockDaysFor retentionMetricsDays;
      };
      loki = {
        bucket = bucketLoki;
        retentionDays = retentionLogsDays;
        lockDays = lockDaysFor retentionLogsDays;
      };
    };

    forBuckets = genAttrs (attrNames bucketSpecs);

    mkBucketAttr = resourceAttr: {
      provider = awsProviderFor awsRegion;
      bucket = "\${aws_s3_bucket.${resourceAttr}.id}";
    };

    loggingTarget = {
      target_bucket = "s3-server-access-logs-${awsOrgId}-${awsRegion}";
      target_prefix = "logs/";
      target_object_key_format.partitioned_prefix.partition_date_source = "EventTime";
    };
  in {
    data.aws_iam_policy_document =
      mapAttrs' (n: _: {
        name = "s3_bucket_policy-${n}";
        value.statement = bucketPolicyStatementSecureTransport "\${aws_s3_bucket.${n}.arn}";
      })
      bucketSpecs;

    resource = {
      aws_s3_bucket = forBuckets (n: {
        provider = awsProviderFor awsRegion;
        inherit (bucketSpecs.${n}) bucket;
        # Object Lock must be enabled at bucket creation; cannot be
        # toggled later.
        object_lock_enabled = true;
      });

      aws_s3_bucket_policy = forBuckets (n:
        mkBucketAttr n
        // {policy = "\${data.aws_iam_policy_document.s3_bucket_policy-${n}.minified_json}";});

      # Object Lock requires versioning enabled.
      aws_s3_bucket_versioning = forBuckets (n:
        mkBucketAttr n
        // {versioning_configuration.status = "Enabled";});

      aws_s3_bucket_object_lock_configuration = forBuckets (n:
        mkBucketAttr n
        // {
          rule.default_retention = {
            mode = "GOVERNANCE";
            days = bucketSpecs.${n}.lockDays;
          };
        });

      aws_s3_bucket_server_side_encryption_configuration = forBuckets (n:
        mkBucketAttr n
        // {rule.apply_server_side_encryption_by_default.sse_algorithm = "AES256";});

      aws_s3_bucket_lifecycle_configuration = forBuckets (n:
        mkBucketAttr n
        // {
          rule = [
            {
              id = "expire-${n}";
              status = "Enabled";
              # Empty filter = applies to every object.
              filter = {};
              expiration.days = bucketSpecs.${n}.retentionDays;
              noncurrent_version_expiration.noncurrent_days = 1;
              abort_incomplete_multipart_upload.days_after_initiation = 7;
            }
          ];
        });

      aws_s3_bucket_logging = forBuckets (n: mkBucketAttr n // loggingTarget);
    };
  };

  # IAM policy granting the EC2 role data-plane access on the Mimir +
  # Loki monitoring buckets. Returns a single tofu policy attrset
  # suitable for placement under `aws_iam_policy.<name>`. The default
  # name is `monitoringS3`; the resource attribute key is the caller's
  # decision.
  #
  # Action list excludes bucket-management calls (DeleteBucket,
  # PutBucketPolicy, PutBucketPublicAccessBlock, …) and governance
  # bypass so a compromised monitoring node cannot destroy or
  # republish historical data.
  mkMonitoringIamPolicy = {
    monitoring,
    defaultTags ? {},
    name ? "monitoringS3",
  }: let
    bucketArns = bucket: [
      "arn:aws:s3:::${bucket}"
      "arn:aws:s3:::${bucket}/*"
    ];
  in {
    inherit name;
    policy = builtins.toJSON {
      Version = "2012-10-17";
      Statement = [
        {
          Effect = "Allow";
          Action = [
            "s3:AbortMultipartUpload"
            "s3:DeleteObject"
            "s3:GetBucketLocation"
            "s3:GetObject"
            "s3:ListBucket"
            "s3:ListMultipartUploadParts"
            "s3:PutObject"
          ];
          Resource =
            bucketArns monitoring.bucketMimir
            ++ bucketArns monitoring.bucketLoki;
        }
      ];
    };
    tags = defaultTags;
  };
}
