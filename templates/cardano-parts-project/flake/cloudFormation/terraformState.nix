{config, ...}: {
  flake.cloudFormation.terraformState = let
    inherit (config.flake.cluster) domain bucketName;
  in {
    AWSTemplateFormatVersion = "2010-09-09";
    Description = "Terraform state handling";

    # Resources here will be created in the AWS_REGION and AWS_PROFILE from your
    # environment variables.
    # Execute this using: `just cf terraformState`

    Resources = {
      kmsKey = {
        Type = "AWS::KMS::Key";
        Properties = {
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
            ];
          };
        };
      };

      kmsKeyAlias = {
        Type = "AWS::KMS::Alias";
        Properties = {
          # This name is used in various places, check before changing it.
          AliasName = "alias/kmsKey";
          TargetKeyId.Ref = "kmsKey";
        };
      };

      DNSZone = {
        Type = "AWS::Route53::HostedZone";
        Properties.Name = domain;
      };

      S3Bucket = {
        Type = "AWS::S3::Bucket";
        DeletionPolicy = "Retain";
        Properties = {
          BucketName = bucketName;
          BucketEncryption.ServerSideEncryptionConfiguration = [
            {
              BucketKeyEnabled = false;
              ServerSideEncryptionByDefault.SSEAlgorithm = "AES256";
            }
          ];
          VersioningConfiguration.Status = "Enabled";
        };
      };

      DynamoDB = {
        Type = "AWS::DynamoDB::Table";
        Properties = {
          TableName = "terraform";

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
        };
      };
    };
  };
}
