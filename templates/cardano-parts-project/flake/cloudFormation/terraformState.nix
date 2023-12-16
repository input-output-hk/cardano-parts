{
  config,
  lib,
  ...
}:
with lib; {
  flake.cloudFormation.terraformState = let
    inherit (config.flake.cardano-parts.cluster.infra.aws) domain bucketName;

    tagWith = name:
      (mapAttrsToList (n: v: {
          Key = n;
          Value = v;
        }) {
          inherit (config.flake.cardano-parts.cluster.infra.generic) organization tribe function repo;
          environment = "generic";
        })
      ++ [
        {
          Key = "Name";
          Value = name;
        }
      ];
  in {
    AWSTemplateFormatVersion = "2010-09-09";
    Description = "Terraform state handling";

    # Resources here will be created in the AWS_REGION and AWS_PROFILE from your
    # environment variables.
    # Execute this using: `just cf terraformState`

    Resources = {
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
        };
      };

      DynamoDB = {
        Type = "AWS::DynamoDB::Table";
        DeletionPolicy = "RetainExceptOnCreate";
        Properties = {
          Tags = tagWith "terraform-DynamoDB";
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
