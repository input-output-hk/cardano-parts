{
  config,
  lib,
  ...
}:
with lib; {
  flake.cloudFormation.terraformState = let
    inherit (config.flake.cardano-parts.cluster.infra.aws) domain bucketName orgId region;

    tagWith = name:
      (mapAttrsToList (n: v: {
          Key = n;
          Value = v;
        }) {
          inherit
            (config.flake.cardano-parts.cluster.infra.generic)
            environment
            function
            organization
            owner
            project
            repo
            tribe
            ;
        })
      ++ [
        {
          Key = "Name";
          Value = name;
        }
        {
          Key = "costCenter";
          Value = {
            Ref = "costCenter";
          };
        }
      ];

    s3ServerAccessLogsBucket = "s3-server-access-logs-${orgId}-${region}";
  in {
    AWSTemplateFormatVersion = "2010-09-09";
    Description = "Terraform state handling";

    # The costCenter parameter will be passed to the configuration via a secrets file.
    # For details, see the just recipe: cf
    Parameters = {
      costCenter = {
        Type = "String";
        Description = "The costCenter tag";
      };
    };

    # Resources here will be created in the AWS_REGION and AWS_PROFILE from your
    # environment variables.
    # Execute this using: `just cf terraformState`
    Resources =
      {
        kmsKey = {
          Type = "AWS::KMS::Key";
          DeletionPolicy = "RetainExceptOnCreate";
          Properties = {
            Tags = tagWith "kmsKey";
            KeyPolicy."Fn::Sub" = builtins.toJSON {
              Version = "2012-10-17";
              Statement = [
                {
                  Action = "kms:*";
                  Effect = "Allow";
                  Principal.AWS = "arn:aws:iam::\${AWS::AccountId}:root";
                  Resource = "*";
                  Sid = "Enable admin use and IAM user permissions";
                }
                {
                  Action = "kms:*";
                  Effect = "Allow";
                  Principal.Service = "logs.${region}.amazonaws.com";
                  Resource = "*";
                  Sid = "Enable CloudWatch to encrypt logs";
                }
              ];
            };
          };
        };

        kmsKeyAlias = {
          Type = "AWS::KMS::Alias";
          DeletionPolicy = "RetainExceptOnCreate";
          Properties = {
            # This name is used in various places, check before changing it.
            # KMS aliases do not accept tags
            AliasName = "alias/kmsKey";
            TargetKeyId.Ref = "kmsKey";
          };
        };

        DNSZone = {
          Type = "AWS::Route53::HostedZone";
          DeletionPolicy = "RetainExceptOnCreate";
          Properties = {
            HostedZoneTags = tagWith domain;
            Name = domain;
          };
        };

        S3BucketS3ServerAccessLogs = {
          Type = "AWS::S3::Bucket";
          DeletionPolicy = "RetainExceptOnCreate";
          Properties = {
            Tags = tagWith bucketName;
            BucketName = s3ServerAccessLogsBucket;
            BucketEncryption.ServerSideEncryptionConfiguration = [
              {
                BucketKeyEnabled = false;
                ServerSideEncryptionByDefault.SSEAlgorithm = "AES256";
              }
            ];
            VersioningConfiguration.Status = "Enabled";
          };
        };

        S3Bucket = {
          Type = "AWS::S3::Bucket";
          DeletionPolicy = "RetainExceptOnCreate";
          Properties = {
            Tags = tagWith bucketName;
            BucketName = bucketName;
            BucketEncryption.ServerSideEncryptionConfiguration = [
              {
                BucketKeyEnabled = false;
                ServerSideEncryptionByDefault.SSEAlgorithm = "AES256";
              }
            ];
            VersioningConfiguration.Status = "Enabled";
            LoggingConfiguration = {
              DestinationBucketName.Ref = "S3BucketS3ServerAccessLogs";
              LogFilePrefix = "logs/";
              TargetObjectKeyFormat.PartitionedPrefix.PartitionDateSource = "EventTime";
            };
          };
        };

        S3BucketPolicyS3ServerAccessLogs = {
          Type = "AWS::S3::BucketPolicy";
          Properties = {
            Bucket.Ref = "S3BucketS3ServerAccessLogs";
            PolicyDocument = {
              Version = "2012-10-17";
              Statement = [
                {
                  Sid = "S3ServerAccessLogsPolicy";
                  Effect = "Allow";
                  Principal.Service = "logging.s3.amazonaws.com";
                  Action = "s3:PutObject";
                  Resource = "arn:aws:s3:::${s3ServerAccessLogsBucket}/*";
                  Condition = {
                    ArnLike."aws:SourceArn" = "arn:aws:s3:::*";
                    StringEquals."aws:SourceAccount" = orgId;
                  };
                }
              ];
            };
          };
        };

        DynamoDB = {
          Type = "AWS::DynamoDB::Table";
          DeletionPolicy = "RetainExceptOnCreate";
          Properties = {
            Tags = tagWith "terraform-DynamoDB";
            TableName = "terraform";

            DeletionProtectionEnabled = true;

            PointInTimeRecoverySpecification = {
              PointInTimeRecoveryEnabled = true;
              RecoveryPeriodInDays = 1;
            };

            KeySchema = [
              {
                AttributeName = "LockID";
                KeyType = "HASH";
              }
            ];

            AttributeDefinitions = [
              {
                AttributeName = "LockID";
                AttributeType = "S";
              }
            ];

            BillingMode = "PAY_PER_REQUEST";

            SSESpecification = {
              SSEEnabled = true;
              SSEType = "KMS";
              KMSMasterKeyId = "alias/kmsKey";
            };
          };
        };
      }
      // lib.mapAttrs' (
        resourceName: bucketName:
          lib.nameValuePair
          "${resourceName}PolicySecureTransport"
          {
            Type = "AWS::S3::BucketPolicy";
            Properties = {
              Bucket.Ref = resourceName;
              PolicyDocument = {
                Version = "2012-10-17";
                Statement = [
                  {
                    Sid = "RestrictToTLSRequestsOnly";
                    Effect = "Deny";
                    Action = "s3:*";
                    Resource = [
                      "arn:aws:s3:::${bucketName}"
                      "arn:aws:s3:::${bucketName}/*"
                    ];
                    Condition.Bool."aws:SecureTransport" = "false";
                    Principal = "*";
                  }
                ];
              };
            };
          }
      ) {
        S3BucketS3ServerAccessLogs = s3ServerAccessLogsBucket;
        S3Bucket = bucketName;
      };
  };
}
