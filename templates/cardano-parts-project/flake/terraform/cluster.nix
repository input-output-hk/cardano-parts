flake @ {
  inputs,
  self,
  lib,
  config,
  ...
}:
with builtins;
with lib; let
  inherit (config.flake.cardano-parts.cluster) group;

  cluster = config.flake.cardano-parts.cluster.infra.aws;

  amis = import "${inputs.nixpkgs}/nixos/modules/virtualisation/ec2-amis.nix";
  awsProviderFor = region: "aws.${underscore region}";
  hyphen = replaceStrings ["."] ["-"];
  underscore = replaceStrings ["-"] ["_"];

  nixosConfigurations = mapAttrs (_: node: node.config) config.flake.nixosConfigurations;
  nodes = filterAttrs (_: node: node.aws != null && node.aws.instance.count > 0) nixosConfigurations;
  mapNodes = f: mapAttrs f nodes;

  regions =
    mapAttrsToList (region: enabled: {
      region = underscore region;
      count =
        if enabled
        then 1
        else 0;
    })
    cluster.regions;

  mapRegions = f: foldl' recursiveUpdate {} (forEach regions f);

  # Generate a list of all multivalue dns resources tf needs to create
  multivalueDnsList = sort lessThan (unique (
    filter (e: e != null) (map (g: getAttrFromPath [g "groupRelayMultivalueDns"] group) (attrNames group))
  ));

  # Different groups can share the same multivalue dns resource.
  # Is node `n` in group `g` a member of the multivalue fqdn `dns`?
  isMultivalueDnsMember = dns: g: n:
    if
      dns
      == group.${g}.groupRelayMultivalueDns
      && hasPrefix "${group.${g}.groupPrefix}${group.${g}.groupRelaySubstring}" n
    then true
    else false;

  # Generate an attrset with attr names of multivalueDns fqdns and attr values of their member node names.
  multivalueDnsAttrs = foldl' (acc: dns:
    recursiveUpdate acc {
      ${dns} = sort lessThan (filter (e: e != null) (flatten (map (g:
        map (n:
          if (isMultivalueDnsMember dns g n)
          then n
          else null)
        (attrNames nodes)) (attrNames group))));
    }) {}
  multivalueDnsList;
in {
  flake.terraform.cluster = inputs.cardano-parts.inputs.terranix.lib.terranixConfiguration {
    system = "x86_64-linux";
    modules = [
      {
        terraform = {
          required_providers = {
            aws.source = "hashicorp/aws";
            null.source = "hashicorp/null";
            local.source = "hashicorp/local";
            tls.source = "hashicorp/tls";
          };

          backend = {
            s3 = {
              inherit (cluster) region;
              bucket = cluster.bucketName;
              key = "terraform";
              dynamodb_table = "terraform";
            };
          };
        };

        provider.aws = forEach (attrNames cluster.regions) (region: {
          inherit region;
          alias = underscore region;
        });

        # Common parameters:
        #   data.aws_caller_identity.current.account_id
        #   data.aws_region.current.name
        data.aws_caller_identity.current = {};
        data.aws_region.current = {};
        data.aws_route53_zone.selected.name = "${cluster.domain}.";

        resource = {
          aws_instance = mapNodes (name: node: {
            inherit (node.aws.instance) count instance_type;
            provider = awsProviderFor node.aws.region;
            ami = amis.${node.system.stateVersion}.${node.aws.region}.hvm-ebs;
            iam_instance_profile = "\${aws_iam_instance_profile.ec2_profile.name}";
            monitoring = true;
            key_name = "\${aws_key_pair.bootstrap_${underscore node.aws.region}[0].key_name}";
            vpc_security_group_ids = [
              "\${aws_security_group.common_${underscore node.aws.region}[0].id}"
            ];
            tags = node.aws.instance.tags or {Name = name;};

            root_block_device = {
              inherit (node.aws.instance.root_block_device) volume_size;
              volume_type = "gp3";
              iops = 3000;
              delete_on_termination = true;
            };

            metadata_options = {
              http_endpoint = "enabled";
              http_put_response_hop_limit = 2;
              http_tokens = "optional";
            };

            lifecycle = [{ignore_changes = ["ami" "user_data"];}];
          });

          aws_iam_instance_profile.ec2_profile = {
            name = "ec2Profile";
            role = "\${aws_iam_role.ec2_role.name}";
          };

          aws_iam_role.ec2_role = {
            name = "ec2Role";
            assume_role_policy = toJSON {
              Version = "2012-10-17";
              Statement = [
                {
                  Action = "sts:AssumeRole";
                  Effect = "Allow";
                  Principal.Service = "ec2.amazonaws.com";
                }
              ];
            };
          };

          aws_iam_role_policy_attachment = let
            mkRoleAttachments = roleResourceName: policyList:
              listToAttrs (map (policy: {
                  name = "${roleResourceName}_policy_attachment_${policy}";
                  value = {
                    role = "\${aws_iam_role.${roleResourceName}.name}";
                    policy_arn = "\${aws_iam_policy.${policy}.arn}";
                  };
                })
                policyList);
          in
            foldl' recursiveUpdate {} [
              (mkRoleAttachments "ec2_role" ["kms_user"])
            ];

          aws_iam_policy.kms_user = {
            name = "kmsUser";
            policy = toJSON {
              Version = "2012-10-17";
              Statement = [
                {
                  Effect = "Allow";
                  Action = ["kms:Decrypt" "kms:DescribeKey"];

                  # KMS `kmsKey` is bootstrapped by cloudFormation rain.
                  # Scope this policy to a specific resource to allow for multiple keys and key policies.
                  Resource = "arn:aws:kms:*:\${data.aws_caller_identity.current.account_id}:key/*";
                  Condition."ForAnyValue:StringLike"."kms:ResourceAliases" = "alias/kmsKey";
                }
              ];
            };
          };

          tls_private_key.bootstrap.algorithm = "ED25519";

          aws_key_pair = mapRegions ({
            count,
            region,
          }: {
            "bootstrap_${region}" = {
              inherit count;
              provider = awsProviderFor region;
              key_name = "bootstrap";
              public_key = "\${tls_private_key.bootstrap.public_key_openssh}";
            };
          });

          aws_eip = mapNodes (name: node: {
            inherit (node.aws.instance) count;
            provider = awsProviderFor node.aws.region;
            instance = "\${aws_instance.${name}[0].id}";
            tags.Name = name;
          });

          aws_eip_association = mapNodes (name: node: {
            inherit (node.aws.instance) count;
            provider = awsProviderFor node.aws.region;
            instance_id = "\${aws_instance.${name}[0].id}";
            allocation_id = "\${aws_eip.${name}[0].id}";
          });

          # To remove or rename a security group, keep it here while removing
          # the reference from the instance. Then apply, and if that succeeds,
          # remove the group here and apply again.
          aws_security_group = let
            mkRule = recursiveUpdate {
              protocol = "tcp";
              cidr_blocks = ["0.0.0.0/0"];
              ipv6_cidr_blocks = ["::/0"];
              prefix_list_ids = [];
              security_groups = [];
              self = true;
            };
          in
            mapRegions ({
              region,
              count,
            }: {
              "common_${region}" = {
                inherit count;
                provider = awsProviderFor region;
                name = "common";
                description = "Allow common ports";
                lifecycle = [{create_before_destroy = true;}];

                ingress = [
                  (mkRule {
                    description = "Allow SSH";
                    from_port = 22;
                    to_port = 22;
                  })
                  (mkRule {
                    description = "Allow Cardano";
                    from_port = 3001;
                    to_port = 3001;
                  })
                  (mkRule {
                    description = "Allow Wireguard";
                    from_port = 51820;
                    to_port = 51820;
                    protocol = "udp";
                  })
                ];

                egress = [
                  (mkRule {
                    description = "Allow outbound traffic";
                    from_port = 0;
                    to_port = 0;
                    protocol = "-1";
                  })
                ];
              };
            });

          aws_route53_record =
            # Generate individual route53 node records
            mapNodes (
              nodeName: _: {
                zone_id = "\${data.aws_route53_zone.selected.zone_id}";
                name = "${nodeName}.\${data.aws_route53_zone.selected.name}";
                type = "A";
                ttl = "300";
                records = ["\${aws_eip.${nodeName}[0].public_ip}"];
              }
            )
            # Generate multivalue route53 records
            // foldl' (acc: dns:
              recursiveUpdate acc (listToAttrs (map (nodeName: {
                  name = "${hyphen dns}-${nodeName}";
                  value = {
                    zone_id = "\${data.aws_route53_zone.selected.zone_id}";
                    name = dns;
                    type = "A";
                    ttl = "300";
                    records = ["\${aws_eip.${nodeName}[0].public_ip}"];
                    multivalue_answer_routing_policy = true;
                    set_identifier = "${hyphen dns}-${nodeName}";
                  };
                })
                multivalueDnsAttrs.${dns}))) {} (attrNames multivalueDnsAttrs);

          local_file.ssh_config = {
            filename = "\${path.module}/.ssh_config";
            file_permission = "0600";
            content = ''
              Host *
                User root
                UserKnownHostsFile /dev/null
                StrictHostKeyChecking no
                IdentityFile .ssh_key
                ServerAliveCountMax 2
                ServerAliveInterval 60

              ${
                concatStringsSep "\n" (map (name: ''
                    Host ${name}
                      HostName ''${aws_eip.${name}[0].public_ip}
                  '')
                  (attrNames nodes))
              }
            '';
          };
        };
      }
    ];
  };
}
