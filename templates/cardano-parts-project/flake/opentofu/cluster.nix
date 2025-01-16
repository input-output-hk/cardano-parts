{
  inputs,
  self,
  lib,
  config,
  ...
}:
with builtins;
with lib; let
  inherit (config.flake.cardano-parts.cluster) infra groups;

  system = "x86_64-linux";

  # IPv6 Configuration:
  #
  #   Default aws vpc provided ipv6 cidr block is /56
  #   Default aws vpc ipv6 subnet size is standard at /64
  #   TF aws_subnet ipv6_cidr_block resource arg must use /64
  #
  # This leaves 8 bits for subnets equal to 2^8 = 256 subnets per vpc each with 2^64 hosts.
  #
  # Refs:
  #   https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html#vpc-sizing-ipv6
  #   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet#ipv6_cidr_block
  #
  ipv6SubnetCidrBits = 64;

  cluster = infra.aws;

  awsProviderFor = region: "aws.${underscore region}";
  hyphen = replaceStrings ["."] ["-"];
  underscore = replaceStrings ["-"] ["_"];

  nixosConfigurations = mapAttrs (_: node: node.config) config.flake.nixosConfigurations;
  nodes = filterAttrs (_: node: node.aws != null && node.aws.instance.count > 0) nixosConfigurations;
  dnsEnabledNodes = filterAttrs (_: node: node.cardano-parts.perNode.meta.enableDns) nodes;

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
  # This will generate a list for either mvDnsAttrName = "bookRelayMultivalueDns" || "groupRelayMultivalueDns"
  mkMultivalueDnsList = mvDnsAttrName:
    sort lessThan (unique (
      filter (e: e != null) (map (g: getAttrFromPath [g mvDnsAttrName] groups) (attrNames groups))
    ));

  # Different groups can share the same multivalue dns resource.
  # Is node `n` in group `g` a member of the multivalue fqdn `dns`?
  isMultivalueDnsMember = mvDnsAttrName: dns: g: n:
    if
      dns
      == groups.${g}.${mvDnsAttrName}
      && hasPrefix "${groups.${g}.groupPrefix}${groups.${g}.groupRelaySubstring}" n
    then true
    else false;

  # Generate an attrset with attr names of multivalueDns fqdns and attr values of their member node names.
  mkMultivalueDnsAttrs = mvDnsAttrName:
    foldl' (acc: dns:
      recursiveUpdate acc {
        ${dns} = sort lessThan (filter (e: e != null) (flatten (map (g:
          map (n:
            if (isMultivalueDnsMember mvDnsAttrName dns g n)
            then n
            else null)
          (attrNames dnsEnabledNodes)) (attrNames groups))));
      }) {};

  mkMultivalueDnsResources = let
    # A five char prefix from an md5 hash is unlikely to collide with only a
    # few registered multivalue dns FQDNs expected per cluster distributed over
    # a 16^5 = 1.6 million range space.
    md5 = dns: substring 0 5 (hashString "md5" dns);
  in
    multivalueDnsAttrs:
      foldl' (acc: dns:
        recursiveUpdate acc (listToAttrs (flatten (map (
            nodeName:
            # Resource names are constrained to 64 chars, so use an md5 hash to
            # shorten them. The full multivalue dns and machine association is
            # still listed in the set_identifier which aws more generously
            # limits to 128 chars.
              [
                {
                  name = "${nodeName}-${md5 dns}";
                  value = {
                    zone_id = "\${data.aws_route53_zone.selected.zone_id}";
                    name = dns;
                    type = "A";
                    ttl = "300";
                    records = ["\${aws_eip.${nodeName}[0].public_ip}"];
                    multivalue_answer_routing_policy = true;
                    set_identifier = "${hyphen dns}-${nodeName}";
                    allow_overwrite = true;
                  };
                }
              ]
              ++ [
                {
                  name = "${nodeName}-${md5 dns}-AAAA";
                  value = {
                    count = "\${length(aws_instance.${nodeName}[0].ipv6_addresses) > 0 ? 1 : 0}";
                    zone_id = "\${data.aws_route53_zone.selected.zone_id}";
                    name = dns;
                    type = "AAAA";
                    ttl = "300";
                    records = ["\${aws_instance.${nodeName}[0].ipv6_addresses[0]}"];
                    multivalue_answer_routing_policy = true;
                    set_identifier = "${hyphen dns}-${nodeName}-AAAA";
                    allow_overwrite = true;
                  };
                }
              ]
          )
          multivalueDnsAttrs.${dns})))) {} (attrNames multivalueDnsAttrs);

  bookMultivalueDnsList = mkMultivalueDnsList "bookRelayMultivalueDns";
  groupMultivalueDnsList = mkMultivalueDnsList "groupRelayMultivalueDns";

  bookMultivalueDnsAttrs = mkMultivalueDnsAttrs "bookRelayMultivalueDns" bookMultivalueDnsList;
  groupMultivalueDnsAttrs = mkMultivalueDnsAttrs "groupRelayMultivalueDns" groupMultivalueDnsList;

  mkCustomRoute53Records = import ./cluster/route53.nix-import;
in {
  flake.opentofu.cluster = inputs.cardano-parts.inputs.terranix.lib.terranixConfiguration {
    inherit system;
    modules = [
      {
        terraform = {
          required_providers = {
            aws.source = "opentofu/aws";
            null.source = "opentofu/null";
            local.source = "opentofu/local";
            tls.source = "opentofu/tls";
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
          default_tags.tags = {
            inherit (infra.generic) organization tribe function repo;
            environment = "generic";
          };
        });

        # Common parameters:
        data = {
          aws_caller_identity.current = {};
          aws_region.current = {};
          aws_route53_zone.selected.name = "${cluster.domain}.";

          aws_ami = mapRegions ({region, ...}: {
            "nixos_${system}_${region}" = {
              owners = ["427812963091"];
              most_recent = true;
              provider = "aws.${region}";

              filter = [
                {
                  name = "name";
                  values = ["nixos/24.11*"];
                }
                {
                  name = "architecture";
                  values = [(builtins.head (splitString "-" system))];
                }
              ];
            };
          });

          # Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html
          aws_availability_zones = mapRegions ({region, ...}: {
            ${region} = {
              provider = "aws.${region}";

              filter = [
                {
                  name = "opt-in-status";
                  values = ["opt-in-not-required"];
                }
              ];
            };
          });

          aws_internet_gateway = mapRegions ({region, ...}: {
            ${region} = {
              provider = "aws.${region}";

              filter = [
                {
                  name = "attachment.vpc-id";
                  values = ["\${data.aws_vpc.${region}.id}"];
                }
              ];

              depends_on = ["data.aws_vpc.${region}"];
            };
          });

          aws_route_table = mapRegions ({region, ...}: {
            ${region} = {
              provider = "aws.${region}";
              route_table_id = "\${data.aws_vpc.${region}.main_route_table_id}";
              depends_on = ["data.aws_vpc.${region}"];
            };
          });

          aws_subnet = mapRegions ({region, ...}: {
            ${region} = {
              provider = "aws.${region}";

              # The index of the map is used to assign an ipv6 subnet network
              # id offset in the aws_default_subnet ipv6_cidr_block resource
              # arg.
              #
              # While az ids are consistent across aws orgs, they are not
              # implemented in all regions, therefore we'll use az names as
              # indexed values.
              #
              # Ref:
              #   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet#availability_zone_id
              #
              for_each = "\${{for i, az in data.aws_availability_zones.${region}.names : i => az}}";
              availability_zone = "\${element(data.aws_availability_zones.${region}.names, each.key)}";
              default_for_az = true;
            };
          });

          aws_vpc = mapRegions ({region, ...}: {
            ${region} = {
              provider = "aws.${region}";
              default = true;
            };
          });
        };

        # Debug output
        # output =
        #   mapRegions ({region, ...}: {
        #     "aws_availability_zones_${region}".value = "\${data.aws_availability_zones.${region}.names}";
        #   })
        #   // mapRegions ({region, ...}: {
        #     "aws_internet_gateway_${region}".value = "\${data.aws_internet_gateway.${region}}";
        #   })
        #   // mapRegions ({region, ...}: {
        #     "aws_route_table_${region}".value = "\${data.aws_route_table.${region}}";
        #   })
        #   // mapRegions ({region, ...}: {
        #     "aws_subnet_${region}".value = "\${data.aws_subnet.${region}}";
        #   })
        #   // mapRegions ({region, ...}: {
        #     "aws_vpc_${region}".value = "\${data.aws_vpc.${region}}";
        #   });

        resource = {
          aws_default_route_table = mapRegions (
            {
              region,
              count,
            }:
              optionalAttrs (count > 0) {
                ${region} = {
                  provider = awsProviderFor region;
                  default_route_table_id = "\${data.aws_vpc.${region}.main_route_table_id}";

                  # The default route, mapping the VPC's CIDR block to "local",
                  # is created implicitly and cannot be specified.
                  # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table
                  #
                  # Json tf format instead of hcl requires all route args explicitly:
                  # https://stackoverflow.com/questions/69760888/terraform-inappropriate-value-for-attribute-route
                  route = let
                    # Terranix strips nulls by default via opt `strip_nulls`.
                    # Instead of disabling default stripping, pass null as a tf expression.
                    args = foldl' (acc: arg: acc // {${arg} = "\${null}";}) {} [
                      "cidr_block"
                      "core_network_arn"
                      "destination_prefix_list_id"
                      "egress_only_gateway_id"
                      "gateway_id"
                      "instance_id"
                      "ipv6_cidr_block"
                      "nat_gateway_id"
                      "network_interface_id"
                      "transit_gateway_id"
                      "vpc_endpoint_id"
                      "vpc_peering_connection_id"
                    ];
                  in
                    map (route: args // route) [
                      {
                        cidr_block = "0.0.0.0/0";
                        gateway_id = "\${data.aws_internet_gateway.${region}.id}";
                      }
                      {
                        ipv6_cidr_block = "::/0";
                        gateway_id = "\${data.aws_internet_gateway.${region}.id}";
                      }
                    ];
                };
              }
          );

          aws_default_subnet = mapRegions ({
            region,
            count,
          }:
            optionalAttrs (count > 0) {
              ${region} = {
                provider = awsProviderFor region;
                for_each = "\${data.aws_subnet.${region}}";

                # Dynamically calculate the subnet bits in case the default
                # CIDR block allocation changes from /56 in the future.
                ipv6_cidr_block = let
                  ipv6CidrBlock = "data.aws_vpc.${region}.ipv6_cidr_block";
                in
                  "\${data.aws_vpc.${region}.ipv6_cidr_block == \"\" ? null :"
                  + " cidrsubnet(${ipv6CidrBlock}, ${toString ipv6SubnetCidrBits} - parseint(tolist(regex(\"/([0-9]+)$\", ${ipv6CidrBlock}))[0], 10), each.key)}";

                availability_zone = "\${each.value.availability_zone}";
              };
            });

          aws_default_vpc = mapRegions (
            {
              region,
              count,
            }:
              optionalAttrs (count > 0) {
                ${region} = {
                  provider = awsProviderFor region;
                  assign_generated_ipv6_cidr_block = true;
                };
              }
          );

          aws_instance = mapNodes (
            name: node: let
              inherit (node.aws) region;
            in
              {
                inherit (node.aws.instance) count instance_type;

                provider = awsProviderFor region;
                ami = "\${data.aws_ami.nixos_${system}_${underscore region}.id}";
                iam_instance_profile = "\${aws_iam_instance_profile.ec2_profile.name}";

                monitoring = true;
                key_name = "\${aws_key_pair.bootstrap_${underscore region}[0].key_name}";
                vpc_security_group_ids = [
                  "\${aws_security_group.common_${underscore region}[0].id}"
                ];
                tags = {Name = name;} // node.aws.instance.tags or {};

                root_block_device = {
                  inherit (node.aws.instance.root_block_device) volume_size;
                  volume_type = "gp3";
                  iops = node.aws.instance.root_block_device.iops or 3000;
                  throughput = node.aws.instance.root_block_device.throughput or 125;
                  delete_on_termination = true;
                  tags =
                    # Root block device tags aren't applied like the other
                    # resources since terraform-aws-provider v5.39.0.
                    #
                    # We need to strip the following tag attrs or tofu
                    # constantly tries to re-apply them.
                    {Name = name;}
                    // removeAttrs (node.aws.instance.tags or {}) ["organization" "tribe" "function" "repo"];
                };

                metadata_options = {
                  http_endpoint = "enabled";
                  http_put_response_hop_limit = 2;
                  http_tokens = "optional";
                };

                lifecycle = [{ignore_changes = ["ami" "user_data"];}];
              }
              // optionalAttrs (node.aws.instance ? availability_zone) {
                inherit (node.aws.instance) availability_zone;
              }
              # Use nix declared ipv6 if available.  This should only be used
              # for public machines where ip exposure in committed code is
              # acceptable and a vanity address is needed. Ie: don't use this
              # for bps.
              #
              # NOTE: As of aws provider 5.66.0, switching from
              # ipv6_address_count to ipv6_addresses will force an instance
              # replacement. If a self-declared ipv6 is required but
              # destroying and re-creating instances to change ipv6 is not
              # acceptable, then until the bug is fixed, continue using
              # auto-assignment only, manually change the ipv6 in the console
              # ui, and run tf apply to update state.
              #
              # Ref: https://github.com/hashicorp/terraform-provider-aws/issues/39433
              // optionalAttrs (node.aws.instance ? ipv6) {
                ipv6_addresses = "\${data.aws_vpc.${underscore region}.ipv6_cidr_block == \"\" ? null : tolist([\"${node.aws.instance.ipv6}\"])}";
              }
              # Otherwise use aws ipv6 auto-assignment
              // optionalAttrs (!(node.aws.instance ? ipv6)) {
                ipv6_address_count = "\${data.aws_vpc.${underscore region}.ipv6_cidr_block == \"\" ? null : 1}";
              }
          );

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
            tags = {Name = name;} // node.aws.instance.tags or {};
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
                    description = "Allow HTTP";
                    from_port = 80;
                    to_port = 80;
                  })
                  (mkRule {
                    description = "Allow HTTPS";
                    from_port = 443;
                    to_port = 443;
                  })
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
                    description = "Allow Forwarding Proxy";
                    from_port = 3132;
                    to_port = 3132;
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
            mapAttrs (
              nodeName: _: {
                zone_id = "\${data.aws_route53_zone.selected.zone_id}";
                name = "${nodeName}.\${data.aws_route53_zone.selected.name}";
                type = "A";
                ttl = "300";
                records = ["\${aws_eip.${nodeName}[0].public_ip}"];
                allow_overwrite = true;
              }
            )
            dnsEnabledNodes
            // mapAttrs' (
              nodeName: _:
                nameValuePair "${nodeName}-AAAA" {
                  # When transitioning into ipv6 dual stack and some instances still have ipv4 only, include the following line.
                  # count = "\${length(aws_instance.${nodeName}[0].ipv6_addresses) > 0 ? 1 : 0}";
                  #
                  # When migration to ipv4/ipv6 dual stack is complete, comment the above line and uncomment the following line.
                  count = "1";

                  zone_id = "\${data.aws_route53_zone.selected.zone_id}";
                  name = "${nodeName}.\${data.aws_route53_zone.selected.name}";
                  type = "AAAA";
                  ttl = "300";
                  records = ["\${aws_instance.${nodeName}[0].ipv6_addresses[0]}"];
                  allow_overwrite = true;
                }
            )
            dnsEnabledNodes
            // mkMultivalueDnsResources bookMultivalueDnsAttrs
            // mkMultivalueDnsResources groupMultivalueDnsAttrs
            // mkCustomRoute53Records;

          # This `.ssh_config` file output format is expected by just recipes
          # such as `list-machines` in order to be parsable.
          local_file.ssh_config = {
            filename = "\${path.module}/.ssh_config";
            file_permission = "0600";
            content = ''
              Host *
                User root
                UserKnownHostsFile /dev/null
                StrictHostKeyChecking no
                ServerAliveCountMax 2
                ServerAliveInterval 60

              ${
                concatStringsSep "\n" (map (name: ''
                    Host ${name}
                      HostName ''${aws_eip.${name}[0].public_ip}

                    Host ${name}.ipv6
                      HostName ''${length(aws_instance.${name}[0].ipv6_addresses) > 0 ? aws_instance.${name}[0].ipv6_addresses[0] : "unavailable.ipv6"}
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
