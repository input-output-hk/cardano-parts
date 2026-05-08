flake: {
  perSystem = {
    lib,
    pkgs,
    system,
    ...
  }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.opsTf-lib = let
        ops = flake.config.flake.cardano-parts.lib.opsTf;

        monitoring = {
          bucketMimir = "test-mimir";
          bucketLoki = "test-loki";
          objectLockMode = "soft";
          retentionMetricsDays = 365;
          retentionLogsDays = 180;
        };

        buckets = ops.mkMonitoringBucketResources {
          inherit monitoring;
          awsRegion = "eu-central-1";
          awsOrgId = "123456789012";
        };

        iamStatement = lib.elemAt (ops.mkMonitoringIamPolicyDoc monitoring).Statement 0;
        iamActions = iamStatement.Action;
        iamResources = iamStatement.Resource;

        mimirLock = buckets.resource.aws_s3_bucket_object_lock_configuration.mimir.rule.default_retention;
        lokiLock = buckets.resource.aws_s3_bucket_object_lock_configuration.loki.rule.default_retention;
        mimirLifecycle = buckets.resource.aws_s3_bucket_lifecycle_configuration.mimir.rule;
        lokiLifecycle = buckets.resource.aws_s3_bucket_lifecycle_configuration.loki.rule;
        secureTransport = buckets.data.aws_iam_policy_document."s3_bucket_policy-mimir".statement;

        requiredActions = ["s3:GetObject" "s3:PutObject" "s3:DeleteObject" "s3:ListBucket"];
        forbiddenActions = [
          "s3:*"
          "s3:DeleteBucket"
          "s3:PutBucketPolicy"
          "s3:PutBucketPublicAccessBlock"
          "s3:DeleteObjectVersion"
          "s3:BypassGovernanceRetention"
        ];

        failures = lib.runTests {
          testBucketsPresent = {
            expr = lib.attrNames buckets.resource.aws_s3_bucket;
            expected = ["loki" "mimir"];
          };
          testVersioningEnabled = {
            expr = buckets.resource.aws_s3_bucket_versioning.mimir.versioning_configuration.status;
            expected = "Enabled";
          };
          testObjectLockEnabled = {
            expr = buckets.resource.aws_s3_bucket.mimir.object_lock_enabled;
            expected = true;
          };
          testSseAlgorithm = {
            expr = buckets.resource.aws_s3_bucket_server_side_encryption_configuration.mimir.rule.apply_server_side_encryption_by_default.sse_algorithm;
            expected = "AES256";
          };
          testLoggingTargetBucket = {
            expr = buckets.resource.aws_s3_bucket_logging.mimir.target_bucket;
            expected = "s3-server-access-logs-123456789012-eu-central-1";
          };

          testLockModeIsGovernance = {
            expr = mimirLock.mode;
            expected = "GOVERNANCE";
          };
          testMimirLockDays = {
            expr = mimirLock.days;
            expected = 1;
          };
          testLokiLockDays = {
            expr = lokiLock.days;
            expected = 1;
          };
          testLockDaysForGovernanceMetrics = {
            expr = ops.lockDaysFor "governance" 365;
            expected = 365;
          };
          testLockDaysForGovernanceLogs = {
            expr = ops.lockDaysFor "governance" 180;
            expected = 180;
          };

          testMimirLifecycleDays = {
            expr = (lib.elemAt mimirLifecycle 0).expiration.days;
            expected = 365;
          };
          testLokiLifecycleDays = {
            expr = (lib.elemAt lokiLifecycle 0).expiration.days;
            expected = 180;
          };
          testDeleteMarkerRule = {
            expr = (lib.elemAt mimirLifecycle 1).expiration.expired_object_delete_marker;
            expected = true;
          };

          testSecureTransportValue = {
            expr = lib.elemAt secureTransport.condition.values 0;
            expected = "false";
          };
          testSecureTransportEffect = {
            expr = secureTransport.effect;
            expected = "Deny";
          };

          testIamMissingActions = {
            expr = lib.subtractLists iamActions requiredActions;
            expected = [];
          };
          testIamForbiddenActions = {
            expr = lib.intersectLists forbiddenActions iamActions;
            expected = [];
          };
          testIamCoversMimirObjects = {
            expr = lib.elem "arn:aws:s3:::test-mimir/*" iamResources;
            expected = true;
          };
          testIamCoversLokiObjects = {
            expr = lib.elem "arn:aws:s3:::test-loki/*" iamResources;
            expected = true;
          };

          testAwsProviderFor = {
            expr = ops.awsProviderFor "eu-central-1";
            expected = "aws.eu_central_1";
          };
        };
      in
        # `throwTestFailures` returns null on pass, throws with a
        # pretty-printed diff on fail. The throw aborts `nix flake
        # check` at eval time before any builder runs.
        builtins.seq
        (lib.debug.throwTestFailures {inherit failures;})
        pkgs.emptyFile;
    };
}
