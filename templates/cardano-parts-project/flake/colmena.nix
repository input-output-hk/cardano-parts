{
  inputs,
  config,
  lib,
  self,
  ...
}: let
  inherit (config.flake) nixosModules nixosConfigurations;
  # inherit (config.flake.cardano-parts.cluster.infra.aws) domain regions;

  cfgGeneric = config.flake.cardano-parts.cluster.infra.generic;
in
  with builtins;
  with lib; {
    flake.colmena = let
      # Region defs:
      eu-central-1.aws.region = "eu-central-1";
      # eu-west-1.aws.region = "eu-west-1";
      # us-east-2.aws.region = "us-east-2";

      # Instance defs:
      t3a-small.aws.instance.instance_type = "t3a.small";
      t3a-medium.aws.instance.instance_type = "t3a.medium";
      m5a-large.aws.instance.instance_type = "m5a.large";

      # Helper fns:
      ebs = size: {aws.instance.root_block_device.volume_size = mkDefault size;};
      # ebsIops = iops: {aws.instance.root_block_device.iops = mkDefault iops;};
      # ebsTp = tp: {aws.instance.root_block_device.throughput = mkDefault tp;};
      # ebsHighPerf = recursiveUpdate (ebsIops 10000) (ebsTp 1000);

      # Helper defs:
      # disableAlertCount.cardano-parts.perNode.meta.enableAlertCount = false;
      # delete.aws.instance.count = 0;

      # Cardano group assignments:
      group = name: {
        cardano-parts.cluster.group = config.flake.cardano-parts.cluster.groups.${name};

        # Since all machines are assigned a group, this is a good place to include default aws instance tags
        aws.instance.tags = {
          inherit (cfgGeneric) organization tribe function repo;
          environment = config.flake.cardano-parts.cluster.groups.${name}.meta.environmentName;
          group = name;
        };
      };

      # Declare a static ipv6. This should only be used for public machines
      # where ip exposure in committed code is acceptable and a vanity address
      # is needed. Ie: don't use this for bps.
      #
      # In the case that a staticIpv6 is not declared, aws will assign one
      # automatically.
      #
      # NOTE: As of aws provider 5.66.0, switching from ipv6_address_count to
      # ipv6_addresses will force an instance replacement. If a self-declared
      # ipv6 is required but destroying and re-creating instances to change
      # ipv6 is not acceptable, then until the bug is fixed, continue using
      # auto-assignment only, manually change the ipv6 in the console ui, and
      # run tf apply to update state.
      #
      # Ref: https://github.com/hashicorp/terraform-provider-aws/issues/39433
      # staticIpv6 = ipv6: {aws.instance.ipv6 = ipv6;};

      # Cardano-node modules for group deployment
      node = {
        imports = [
          # Base cardano-node service
          config.flake.cardano-parts.cluster.groups.default.meta.cardano-node-service

          # Config for cardano-node group deployments
          inputs.cardano-parts.nixosModules.profile-cardano-node-group
          inputs.cardano-parts.nixosModules.profile-cardano-custom-metrics

          # Until 10.5 is released -- see description below
          absPeerSnap
        ];
      };

      # mkCustomNode = flakeInput:
      #   node
      #   // {
      #     cardano-parts.perNode = {
      #       pkgs = {inherit (inputs.${flakeInput}.packages.x86_64-linux) cardano-cli cardano-node cardano-submit-api;};
      #     };
      #   };

      # Mithril signing config
      # mithrilRelay = {imports = [inputs.cardano-parts.nixosModules.profile-mithril-relay];};
      # declMRel = node: {services.mithril-signer.relayEndpoint = nixosConfigurations.${node}.config.ips.privateIpv4 or "ip-module not available";};
      # declMSigner = node: {services.mithril-relay.signerIp = nixosConfigurations.${node}.config.ips.privateIpv4 or "ip-module not available;};

      # Optimize tcp sysctl and route params for long distance transmission.
      # Apply to one relay per pool group.
      # Ref: https://forum.cardano.org/t/problem-with-increasing-blocksize-or-processing-requirements/140044
      tcpTxOpt = {pkgs, ...}: {
        boot.kernel.sysctl."net.ipv4.tcp_slow_start_after_idle" = 0;

        systemd.services.tcp-tx-opt = {
          after = ["network-online.target"];
          wants = ["network-online.target"];
          wantedBy = ["multi-user.target"];

          path = with pkgs; [gnugrep iproute2];
          script = ''
            set -euo pipefail

            APPEND_OPTS="initcwnd 42 initrwnd 42"

            echo "Evalulating -4 default route options..."
            DEFAULT_ROUTE=""
            while [ "$DEFAULT_ROUTE" = "" ]; do
              echo "Waiting for the -4 default route to populate..."
              sleep 2
              DEFAULT_ROUTE=$(ip route list default)
            done

            CHANGE_ROUTE() {
              PROT="$1"
              DEFAULT_ROUTE="$2"

              echo "Current default $PROT route is: $DEFAULT_ROUTE"

              if ! grep -q initcwnd <<< "$DEFAULT_ROUTE"; then
                echo "Adding tcp window size options to the $PROT default route..."
                eval ip "$PROT" route change "$DEFAULT_ROUTE" "$APPEND_OPTS"
              else
                echo "The $PROT default route already contains an initcwnd customization, skipping."
              fi
            }

            CHANGE_ROUTE "-4" "$DEFAULT_ROUTE"

            DEFAULT_ROUTE=$(ip -6 route list default)
            if [ "$DEFAULT_ROUTE" = "" ]; then
              echo "The -6 default route is not set, skipping."
            else
              CHANGE_ROUTE "-6" "$DEFAULT_ROUTE"
            fi
          '';

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      };

      # Profiles
      pre = {imports = [inputs.cardano-parts.nixosModules.profile-pre-release];};

      smash = {
        imports = [
          config.flake.cardano-parts.cluster.groups.default.meta.cardano-smash-service
          inputs.cardano-parts.nixosModules.profile-cardano-smash
          {services.cardano-smash.acmeEmail = "devops@iohk.io";}
        ];
      };

      # Snapshots: add this to a dbsync machine defn and deploy; remove once the snapshot is restored.
      # Snapshots for mainnet can be found at: https://update-cardano-mainnet.iohk.io/cardano-db-sync/index.html
      # snapshot = {services.cardano-db-sync.restoreSnapshot = "$SNAPSHOT_URL";};

      # Topology profiles
      # Note: not including a topology profile will default to edge topology if module profile-cardano-node-group is imported
      topoBp = {imports = [inputs.cardano-parts.nixosModules.profile-cardano-node-topology {services.cardano-node-topology = {role = "bp";};}];};
      topoRel = {imports = [inputs.cardano-parts.nixosModules.profile-cardano-node-topology {services.cardano-node-topology = {role = "relay";};}];};

      # Roles
      bp = {
        imports = [
          inputs.cardano-parts.nixosModules.role-block-producer
          topoBp
          # Disable machine DNS creation for block producers to avoid ip discovery
          {cardano-parts.perNode.meta.enableDns = false;}
        ];
      };
      rel = {imports = [inputs.cardano-parts.nixosModules.role-relay topoRel];};

      dbsync = {
        imports = [
          config.flake.cardano-parts.cluster.groups.default.meta.cardano-node-service
          config.flake.cardano-parts.cluster.groups.default.meta.cardano-db-sync-service
          inputs.cardano-parts.nixosModules.profile-cardano-db-sync
          inputs.cardano-parts.nixosModules.profile-cardano-node-group
          inputs.cardano-parts.nixosModules.profile-cardano-custom-metrics
          inputs.cardano-parts.nixosModules.profile-cardano-postgres
          {services.cardano-node.shareNodeSocket = true;}
          {services.cardano-postgres.enablePsqlrc = true;}

          # Until 10.5 is released -- see description below
          absPeerSnap
        ];
      };

      faucet = {
        imports = [
          # TODO: Module import fixup for local services
          # config.flake.cardano-parts.cluster.groups.default.meta.cardano-faucet-service
          inputs.cardano-parts.nixosModules.service-cardano-faucet

          inputs.cardano-parts.nixosModules.profile-cardano-faucet
          {services.cardano-faucet.acmeEmail = "devops@iohk.io";}
        ];
      };

      # Until 10.5.x is released, 10.4.1 will fail to start without this because
      # node doesn't yet properly look up the relative path from topology to
      # peer snapshot file.
      #
      # Setting this option null fixes the problem, but will leave a
      # dangling peer snapshot file until 10.6.
      #
      # So until then, we'll switch from relative path that causes node failure
      # to absolute path which does not.
      absPeerSnap = {services.cardano-node.peerSnapshotFile = i: "/etc/cardano-node/peer-snapshot-${toString i}.json";};
    in {
      meta = {
        nixpkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
        };

        nodeSpecialArgs =
          foldl'
          (acc: node: let
            instanceType = node: nixosConfigurations.${node}.config.aws.instance.instance_type;
          in
            recursiveUpdate acc {
              ${node} = {
                nodeResources = {
                  inherit
                    (config.flake.cardano-parts.aws.ec2.spec.${instanceType node})
                    provider
                    coreCount
                    cpuCount
                    memMiB
                    nodeType
                    threadsPerCore
                    ;
                };
              };
            })
          {} (attrNames nixosConfigurations);
      };

      defaults.imports = [
        inputs.cardano-parts.nixosModules.module-aws-ec2
        inputs.cardano-parts.nixosModules.profile-aws-ec2-ephemeral
        inputs.cardano-parts.nixosModules.profile-cardano-parts
        inputs.cardano-parts.nixosModules.profile-basic
        inputs.cardano-parts.nixosModules.profile-common
        inputs.cardano-parts.nixosModules.profile-grafana-alloy
        nixosModules.common
        nixosModules.ip-module-check
      ];

      preview1-bp-a-1 = {imports = [eu-central-1 t3a-small (ebs 40) (group "preview1") node bp];};
      preview1-rel-a-1 = {imports = [eu-central-1 t3a-small (ebs 40) (group "preview1") node rel];};
      preview1-rel-b-1 = {imports = [eu-central-1 t3a-small (ebs 40) (group "preview1") node rel];};
      preview1-rel-c-1 = {imports = [eu-central-1 t3a-small (ebs 40) (group "preview1") node rel tcpTxOpt];};
      preview1-dbsync-a-1 = {imports = [eu-central-1 m5a-large (ebs 40) (group "preview1") dbsync smash];};
      preview1-faucet-a-1 = {imports = [eu-central-1 t3a-medium (ebs 40) (group "preview1") node faucet pre];};
    };

    flake.colmenaHive = inputs.cardano-parts.inputs.colmena.lib.makeHive self.outputs.colmena;
  }
