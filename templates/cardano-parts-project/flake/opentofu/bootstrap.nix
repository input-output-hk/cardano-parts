{
  inputs,
  lib,
  config,
  ...
}: let
  inherit (config.flake.lib.strings) dashToSnake;

  inherit (config.flake.cardano-parts.cluster) infra;

  system = "x86_64-linux";

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

  unmanagedBuckets = ["rain_artifacts"];

  workspace = "bootstrap";

  awsProviderFor = region: "aws.${dashToSnake region}";
  awsccProviderFor = region: "awscc.${dashToSnake region}";

  sensitiveString = {
    type = "string";
    sensitive = true;
    nullable = false;
  };
in {
  flake.opentofu.${workspace} = inputs.cardano-parts.inputs.terranix.lib.terranixConfiguration {
    strip_nulls = false;
    inherit system;
    modules = [
      {
        terraform = {
          required_providers = {
            aws.source = "opentofu/aws";
            awscc.source = "opentofu/awscc";
            external.source = "opentofu/external";
          };

          backend = {
            s3 = {
              inherit (infra.aws) region;
              bucket = infra.aws.bucketName;
              key = "terraform";
              dynamodb_table = "terraform";
            };
          };
        };

        variable = {
          # costCenter tag should remain secret in public repos
          ${infra.generic.costCenter} = sensitiveString;
        };

        provider = {
          aws = lib.forEach (lib.attrNames infra.aws.regions) (region: {
            inherit region;
            alias = dashToSnake region;
            default_tags.tags = {
              inherit
                (infra.generic)
                environment
                function
                organization
                owner
                project
                repo
                tribe
                ;

              # costCenter is saved as a secret
              costCenter = "\${var.${infra.generic.costCenter}}";

              TerraformWorkspace = workspace;
              TerraformState = "s3://${infra.aws.bucketName}/env:/${workspace}/terraform";
            };
          });

          awscc = lib.forEach (lib.attrNames infra.aws.regions) (region: {
            inherit region;
            alias = dashToSnake region;
          });
        };
      }

      # Configure rain's and CloudFormation's buckets.
      {
        data = {
          awscc_s3_buckets.this = {
            provider = awsccProviderFor infra.aws.region;
          };

          aws_iam_policy_document = lib.listToAttrs (
            lib.forEach unmanagedBuckets (
              name:
                lib.nameValuePair "s3_bucket_policy-${name}" {
                  statement = bucketPolicyStatementSecureTransport "arn:aws:s3:::\${local.aws_s3_bucket-${name}-id}";
                }
            )
          );
        };

        locals = {
          aws_s3_bucket-rain_artifacts-id = assert lib.elem "rain_artifacts" unmanagedBuckets;
            lib.trim ''
              ''${one([for bucket in data.awscc_s3_buckets.this.ids : bucket if length(regexall("rain-artifacts-\\d{12}-${infra.aws.region}", bucket)) > 0])}
            '';
        };

        resource = {
          aws_s3_bucket_policy = lib.genAttrs unmanagedBuckets (name: {
            bucket = "\${local.aws_s3_bucket-${name}-id}";
            policy = "\${data.aws_iam_policy_document.s3_bucket_policy-${name}.minified_json}";
          });

          aws_s3_bucket_versioning = lib.genAttrs unmanagedBuckets (name: {
            bucket = "\${local.aws_s3_bucket-${name}-id}";
            versioning_configuration.status = "Enabled";
          });
        };
      }

      # This creates the AMI for our EC2 instances.
      # It is done here in the bootstrap workspace
      # to avoid slowing down evaluation of the other workspaces
      # because we change them much more frequently.
      {
        data = {
          external."ami_nixos_${system}".program = [
            "nu"
            "--commands"
            ''
              $'(
                nix build
                --out-link .terraform/ami_nixos_${system}
                --print-out-paths
                .#packages.${system}.ami
              )/nix-support/image-info.json'
              | open
              | insert disk_root $in.disks.root.file
              | insert disk_boot $in.disks.boot.file
              | insert disk_root_basename ($in.disks.root.file | path basename)
              | insert disk_boot_basename ($in.disks.boot.file | path basename)
              | reject disks
              | to json
            ''
          ];

          aws_iam_policy_document = {
            kms_key-amis.statement = {
              effect = "Allow";
              actions = ["kms:*"];
              principals = {
                type = "AWS";
                identifiers = ["arn:aws:iam::${infra.aws.orgId}:root"];
              };
              resources = ["*"];
              sid = "Enable admin use and IAM user permissions";
            };

            s3_bucket_policy-amis.statement = bucketPolicyStatementSecureTransport "\${aws_s3_bucket.amis.arn}";

            iam_role-vmimport.statement = {
              effect = "Allow";
              actions = ["sts:AssumeRole"];
              principals = {
                type = "Service";
                identifiers = ["vmie.amazonaws.com"];
              };
              condition = {
                test = "StringEquals";
                variable = "sts:ExternalId";
                values = ["vmimport"];
              };
            };

            iam_role_policy-vmimport.statement = [
              {
                effect = "Allow";
                actions = [
                  "s3:GetBucketLocation"
                  "s3:GetObject"
                  "s3:ListBucket"
                ];
                resources = [
                  "\${aws_s3_bucket.amis.arn}"
                  "\${aws_s3_bucket.amis.arn}/*"
                ];
              }
              {
                effect = "Allow";
                actions = [
                  "ec2:ModifySnapshotAttribute"
                  "ec2:CopySnapshot"
                  "ec2:RegisterImage"
                  "ec2:Describe*"
                ];
                resources = ["*"];
              }
              {
                effect = "Allow";
                actions = [
                  "kms:CreateGrant"
                  "kms:Decrypt"
                  "kms:DescribeKey"
                  "kms:Encrypt"
                  "kms:GenerateDataKey*"
                  "kms:ReEncrypt*"
                ];
                resources = ["*"];
              }
            ];
          };
        };

        resource = {
          # KMS keys for AMI encryption in all regions
          aws_kms_key =
            {
              amis = {
                provider = awsProviderFor infra.aws.region;
                description = "Key to encrypt AMIs with";
                enable_key_rotation = true;
                policy = "\${data.aws_iam_policy_document.kms_key-amis.minified_json}";
              };
            }
            // lib.listToAttrs (
              lib.forEach
              (lib.filter (r: r != infra.aws.region) (lib.attrNames infra.aws.regions))
              (region:
                lib.nameValuePair "amis_${dashToSnake region}" {
                  provider = awsProviderFor region;
                  description = "Key to encrypt AMIs with in ${region}";
                  enable_key_rotation = true;
                  policy = "\${data.aws_iam_policy_document.kms_key-amis.minified_json}";
                })
            );

          aws_kms_alias =
            {
              amis = {
                provider = awsProviderFor infra.aws.region;
                name = "alias/amis";
                target_key_id = "\${aws_kms_key.amis.id}";
              };
            }
            // lib.listToAttrs (
              lib.forEach
              (lib.filter (r: r != infra.aws.region) (lib.attrNames infra.aws.regions))
              (region:
                lib.nameValuePair "amis_${dashToSnake region}" {
                  provider = awsProviderFor region;
                  name = "alias/amis";
                  target_key_id = "\${aws_kms_key.amis_${dashToSnake region}.id}";
                })
            );

          aws_ami."nixos_${system}" = rec {
            provider = awsProviderFor infra.aws.region;
            name = "NixOS/${tags.system}/${tags.version}";
            virtualization_type = "hvm";
            architecture = lib.trim ''
              ''${
                {
                  "i386" = "i386",
                  "x86_64" = "x86_64",
                  "aarch64" = "arm64",
                }[one(slice(split("-", "${tags.system}"), 0, 1))]
              }''${
                lookup(
                  {"darwin" = "_mac"},
                  one(slice(reverse(split("-", "${tags.system}")), 0, 1)),
                  ""
                )
              }
            '';
            boot_mode = "\${data.external.ami_nixos_${system}.result.boot_mode}";
            root_device_name = "/dev/xvda";
            ena_support = true;
            imds_support = "v2.0";
            ebs_block_device = [
              {
                device_name = "/dev/xvda";
                snapshot_id = "\${aws_ebs_snapshot_import.ami_nixos_${system}_root.id}";
              }
              {
                device_name = "/dev/xvdb";
                snapshot_id = "\${aws_ebs_snapshot_import.ami_nixos_${system}_boot.id}";
              }
            ];
            tags = {
              system = "\${data.external.ami_nixos_${system}.result.system}";
              version = "\${data.external.ami_nixos_${system}.result.label}";
            };
          };

          # Copy AMI to all other regions
          aws_ami_copy = lib.listToAttrs (
            lib.forEach
            (lib.filter (r: r != infra.aws.region) (lib.attrNames infra.aws.regions))
            (region:
              lib.nameValuePair "nixos_${system}_${dashToSnake region}" {
                provider = awsProviderFor region;
                name = "NixOS/\${aws_ami.nixos_${system}.tags.system}/\${aws_ami.nixos_${system}.tags.version}";
                source_ami_id = "\${aws_ami.nixos_${system}.id}";
                source_ami_region = infra.aws.region;
                encrypted = true;
                kms_key_id = "\${aws_kms_key.amis_${dashToSnake region}.arn}";
                tags = {
                  system = "\${aws_ami.nixos_${system}.tags.system}";
                  version = "\${aws_ami.nixos_${system}.tags.version}";
                  source_region = infra.aws.region;
                };
              })
          );

          aws_ebs_snapshot_import = lib.listToAttrs (
            lib.forEach ["root" "boot"] (
              name:
                lib.nameValuePair "ami_nixos_${system}_${name}" {
                  provider = awsProviderFor infra.aws.region;
                  disk_container = {
                    format = "VHD";
                    user_bucket = {
                      s3_bucket = "\${aws_s3_bucket.amis.id}";
                      s3_key = "\${aws_s3_object.ami_nixos_${system}_${name}.key}";
                    };
                  };
                  role_name = "\${aws_iam_role.vmimport.name}";
                  encrypted = true;
                  kms_key_id = "\${aws_kms_key.amis.arn}";
                  tags = {
                    Name = "ami_nixos_${system}_${name}";
                    inherit system;
                    disk = name;
                  };

                  lifecycle.replace_triggered_by = [
                    "aws_s3_object.ami_nixos_${system}_${name}.source"
                  ];
                }
            )
          );

          aws_s3_bucket.amis = {
            provider = awsProviderFor infra.aws.region;
            bucket = "${infra.aws.profile}-amis";
            force_destroy = true;
          };

          aws_s3_bucket_server_side_encryption_configuration.amis = {
            provider = awsProviderFor infra.aws.region;
            bucket = "\${aws_s3_bucket.amis.id}";
            rule.apply_server_side_encryption_by_default = {
              sse_algorithm = "aws:kms";
              kms_master_key_id = "\${aws_kms_key.amis.id}";
            };
          };

          aws_s3_bucket_policy.amis = {
            provider = awsProviderFor infra.aws.region;
            bucket = "\${aws_s3_bucket.amis.id}";
            policy = "\${data.aws_iam_policy_document.s3_bucket_policy-amis.minified_json}";
          };

          aws_s3_object = lib.listToAttrs (
            lib.forEach ["root" "boot"] (
              name:
                lib.nameValuePair "ami_nixos_${system}_${name}" {
                  provider = awsProviderFor infra.aws.region;
                  bucket = "\${aws_s3_bucket.amis.id}";
                  key = "\${data.external.ami_nixos_${system}.result.disk_${name}_basename}";
                  source = "\${data.external.ami_nixos_${system}.result.disk_${name}}";
                }
            )
          );

          aws_s3_bucket_logging =
            {
              amis = {
                provider = awsProviderFor infra.aws.region;
                bucket = "\${aws_s3_bucket.amis.id}";
                target_bucket = with infra.aws; "s3-server-access-logs-${orgId}-${region}";
                target_prefix = "logs/";
                target_object_key_format.partitioned_prefix.partition_date_source = "EventTime";
              };
            }
            // lib.listToAttrs (
              lib.forEach unmanagedBuckets (
                name:
                  lib.nameValuePair name {
                    provider = awsProviderFor infra.aws.region;
                    bucket = "\${local.aws_s3_bucket-${name}-id}";
                    target_bucket = with infra.aws; "s3-server-access-logs-${orgId}-${region}";
                    target_prefix = "logs/";
                    target_object_key_format.partitioned_prefix.partition_date_source = "EventTime";
                  }
              )
            );

          aws_s3_bucket_versioning.amis = {
            provider = awsProviderFor infra.aws.region;
            bucket = "\${aws_s3_bucket.amis.id}";
            versioning_configuration.status = "Enabled";
          };

          aws_iam_role.vmimport = rec {
            provider = awsProviderFor infra.aws.region;
            name = "vmimport";
            assume_role_policy = "\${data.aws_iam_policy_document.iam_role-${name}.minified_json}";
          };

          # https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html
          aws_iam_role_policy.vmimport = rec {
            provider = awsProviderFor infra.aws.region;
            name = "vmimport";
            role = "\${aws_iam_role.${name}.id}";
            policy = "\${data.aws_iam_policy_document.iam_role_policy-${name}.minified_json}";
          };
        };
      }
    ];
  };
}
