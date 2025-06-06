# nixosModule: profile-cardano-parts
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.cardano-parts.cluster.group.<...>                             # Inherited from flakeModule cluster.group assignment
#   config.cardano-parts.perNode.generic.abortOnMissingIpModule
#   config.cardano-parts.perNode.generic.warnOnMissingIpModule
#   config.cardano-parts.perNode.lib.cardanoLib
#   config.cardano-parts.perNode.lib.opsLib
#   config.cardano-parts.perNode.lib.topologyLib
#   config.cardano-parts.perNode.meta.addressType
#   config.cardano-parts.perNode.meta.blockfrost-platform-service
#   config.cardano-parts.perNode.meta.cardanoDbSyncPrometheusExporterPort
#   config.cardano-parts.perNode.meta.cardanoNodePort
#   config.cardano-parts.perNode.meta.cardanoNodePrometheusExporterPort
#   config.cardano-parts.perNode.meta.cardanoSmashDelistedPools
#   config.cardano-parts.perNode.meta.cardano-db-sync-service
#   config.cardano-parts.perNode.meta.cardano-faucet-service
#   config.cardano-parts.perNode.meta.cardano-metadata-service
#   config.cardano-parts.perNode.meta.cardano-node-service
#   config.cardano-parts.perNode.meta.cardano-ogmios-service
#   config.cardano-parts.perNode.meta.cardano-smash-service
#   config.cardano-parts.perNode.meta.cardano-tracer-service
#   config.cardano-parts.perNode.meta.enableAlertCount
#   config.cardano-parts.perNode.meta.enableDns
#   config.cardano-parts.perNode.meta.hostAddr
#   config.cardano-parts.perNode.meta.hostAddrIpv6
#   config.cardano-parts.perNode.meta.hostsList
#   config.cardano-parts.perNode.meta.nodeId
#   config.cardano-parts.perNode.pkgs.blockperf
#   config.cardano-parts.perNode.pkgs.cardano-cli
#   config.cardano-parts.perNode.pkgs.cardano-db-sync
#   config.cardano-parts.perNode.pkgs.cardano-db-sync-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-db-tool
#   config.cardano-parts.perNode.pkgs.cardano-faucet
#   config.cardano-parts.perNode.pkgs.cardano-metadata-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-node
#   config.cardano-parts.perNode.pkgs.cardano-node-pkgs
#   config.cardano-parts.perNode.pkgs.cardano-ogmios
#   config.cardano-parts.perNode.pkgs.cardano-smash
#   config.cardano-parts.perNode.pkgs.cardano-submit-api
#   config.cardano-parts.perNode.pkgs.cardano-tracer
#   config.cardano-parts.perNode.pkgs.mithril-client-cli
#   config.cardano-parts.perNode.pkgs.mithril-signer
#   config.cardano-parts.perNode.roles.isCardanoDensePool
flake @ {moduleWithSystem, ...}: {
  flake.nixosModules.profile-cardano-parts = moduleWithSystem ({system}: {
    config,
    lib,
    pkgs,
    nodes,
    name,
    ...
  }: let
    inherit (builtins) attrNames deepSeq elem head stringLength;
    inherit (lib) count filterAttrs foldl' isList mapAttrsToList mdDoc mapAttrs' mkIf mkOption nameValuePair optional optionalString pipe recursiveUpdate types;
    inherit (types) anything attrsOf bool enum ints listOf oneOf package port nullOr str submodule;
    inherit (cfg.group) groupFlake;
    inherit (cfgPerNode.lib) topologyLib;

    cfg = config.cardano-parts.cluster;
    cfgPerNode = config.cardano-parts.perNode;

    mkBoolOpt = mkOption {
      type = bool;
      default = false;
    };

    mkPkgOpt = name: pkg: {
      ${name} = mkOption {
        type = package;
        description = mdDoc "The cardano-parts nixos default package for ${name}.";
        default = pkg;
      };
    };

    mkSpecialOpt = name: type: specialPkg: {
      ${name} = mkOption {
        inherit type;
        description = mdDoc "The cardano-parts nixos default special package for ${name}.";
        default = specialPkg;
      };
    };

    mainSubmodule = submodule {
      options = {
        cluster = mkOption {
          type = clusterSubmodule;
          description = mdDoc "Cardano-parts nixos cluster submodule";
          default = {};
        };

        perNode = mkOption {
          type = perNodeSubmodule;
          description = mdDoc "Cardano-parts nixos perNode submodule";
          default = {};
        };
      };
    };

    clusterSubmodule = submodule {
      options = {
        group = mkOption {
          type = attrsOf anything;
          inherit (flake.config.flake.cardano-parts.cluster.groups) default;
          description = mdDoc "The cardano group to associate with the nixos node.";
        };
      };
    };

    perNodeSubmodule = submodule {
      options = {
        generic = mkOption {
          type = genericSubmodule;
          description = mdDoc "Cardano-parts nixos perNode generic submodule";
          default = {};
        };

        lib = mkOption {
          type = libSubmodule;
          description = mdDoc "Cardano-parts nixos perNode lib submodule";
          default = {};
        };

        meta = mkOption {
          type = metaSubmodule;
          description = mdDoc "Cardano-parts nixos perNode meta submodule";
          default = {};
        };

        pkgs = mkOption {
          type = pkgsSubmodule;
          description = mdDoc "Cardano-parts nixos perNode pkgs submodule";
          default = {};
        };

        roles = mkOption {
          type = rolesSubmodule;
          description = mdDoc "Cardano-parts nixos perNode roles submodule";
          default = {};
        };
      };
    };

    genericSubmodule = submodule {
      options = {
        abortOnMissingIpModule = mkOption {
          type = bool;
          description = mdDoc ''
            The option to abort on missing downstream provided "ip-module" nixosModule.
          '';
          default = cfg.group.generic.abortOnMissingIpModule;
        };

        warnOnMissingIpModule = mkOption {
          type = bool;
          description = mdDoc ''
            The option to warn on missing downstream provided "ip-module" nixosModule.
          '';
          default = cfg.group.generic.warnOnMissingIpModule;
        };
      };
    };

    libSubmodule = submodule {
      options = foldl' recursiveUpdate {} [
        (mkSpecialOpt "cardanoLib" (attrsOf anything) (cfg.group.lib.cardanoLib system))
        (mkSpecialOpt "opsLib" (attrsOf anything) (cfg.group.lib.opsLib pkgs))
        (mkSpecialOpt "topologyLib" (attrsOf anything) (cfg.group.lib.topologyLib cfg.group))
      ];
    };

    metaSubmodule = submodule {
      options = {
        addressType = mkOption {
          type = enum ["fqdn" "namePrivateIpv4" "namePublicIpv4" "namePublicIpv6" "privateIpv4" "publicIpv4" "publicIpv6"];
          description = mdDoc "The default addressType for topologyLib mkProducer function.";
          default = cfg.group.meta.addressType;
        };

        blockfrost-platform-service = mkOption {
          type = str;
          description = mdDoc "The blockfrost-platform-service import path string.";
          default = cfg.group.meta.blockfrost-platform-service;
        };

        cardanoDbSyncPrometheusExporterPort = mkOption {
          type = port;
          description = mdDoc "The port to associate with the nixos cardano-db-sync prometheus exporter.";
          default = cfg.group.meta.cardanoDbSyncPrometheusExporterPort;
        };

        cardanoNodePort = mkOption {
          type = port;
          description = mdDoc "The port to associate with the nixos cardano-node.";
          default = cfg.group.meta.cardanoNodePort;
        };

        cardanoNodePrometheusExporterPort = mkOption {
          type = port;
          description = mdDoc "The port to associate with the nixos cardano-node prometheus exporter.";
          default = cfg.group.meta.cardanoNodePrometheusExporterPort;
        };

        cardanoSmashDelistedPools = mkOption {
          type = listOf str;
          description = mdDoc "The cardano-smash delisted pools.";
          default = cfg.group.meta.cardanoSmashDelistedPools;
        };

        cardano-db-sync-service = mkOption {
          type = str;
          description = mdDoc "The cardano-db-sync-service import path string.";
          default = cfg.group.meta.cardano-db-sync-service;
        };

        cardano-faucet-service = mkOption {
          type = str;
          description = mdDoc "The cardano-faucet-service import path string.";
          default = cfg.group.meta.cardano-faucet-service;
        };

        cardano-metadata-service = mkOption {
          type = str;
          description = mdDoc "The cardano-metadata-service import path string.";
          default = cfg.group.meta.cardano-metadata-service;
        };

        cardano-node-service = mkOption {
          type = str;
          description = mdDoc "The cardano-node-service import path string.";
          default = cfg.group.meta.cardano-node-service;
        };

        cardano-ogmios-service = mkOption {
          type = str;
          description = mdDoc "The cardano-ogmios-service import path string.";
          default = cfg.group.meta.cardano-ogmios-service;
        };

        cardano-smash-service = mkOption {
          type = str;
          description = mdDoc "The cardano-smash-service import path string.";
          default = cfg.group.meta.cardano-smash-service;
        };

        cardano-tracer-service = mkOption {
          type = str;
          description = mdDoc "The cardano-tracer-service import path string.";
          default = cfg.group.meta.cardano-tracer-service;
        };

        enableAlertCount = mkOption {
          type = bool;
          description = mdDoc ''
            Whether to count this machine as an expected machine to appear in grafana/prometheus metrics.

            In cases where this machine may be created, but mostly kept in a stopped state such that it will
            not push metrics to the monitoring server, this option can be disabled to exclude it from the
            expected machine count.

            The value of this boolean will affect the alert rules applied by running `just tofu grafana apply`
            from a cardano-parts ops devShell.
          '';
          default = true;
        };

        enableDns = mkOption {
          type = bool;
          description = mdDoc ''
            Whether to create a DNS for this machine when running `just tofu apply`.

            Typically, only block producers or other sensitive machines would want to set this to false.
          '';
          default = true;
        };

        hostAddr = mkOption {
          type = str;
          description = mdDoc "The hostAddr to associate with the nixos cardano-node for ipv4 binding.";
          default = "0.0.0.0";
        };

        hostAddrIpv6 = mkOption {
          type = str;
          description = mdDoc "The hostAddr to associate with the nixos cardano-node for ipv6 binding.";
          default = "::0";
        };

        hostsList = mkOption {
          type = oneOf [(enum ["all" "group"]) (listOf str)];
          description = mdDoc ''
            A list of Colmena machine names for which /etc/hosts will be configured for if
            nixosModule.ip-module is available in the downstream repo and profile-cardano-parts
            nixosModule is imported.

            If instead of a list, this option is configured with a string of "all", all
            Colmena machine names in the cluster will be used for the /etc/hosts file.

            If configured with a string of "group" then all Colmena machine names in the
            same group will be used for the /etc/hosts file.
          '';
          default = cfg.group.meta.hostsList;
        };

        nodeId = mkOption {
          type = nullOr ints.unsigned;
          description = mdDoc "The hostAddr to associate with the nixos cardano-node.";
          default = 0;
        };
      };
    };

    pkgsSubmodule = submodule {
      options = foldl' recursiveUpdate {} [
        (mkPkgOpt "blockperf" (cfg.group.pkgs.blockperf system))
        (mkPkgOpt "cardano-cli" (cfg.group.pkgs.cardano-cli system))
        (mkPkgOpt "cardano-db-sync" (cfg.group.pkgs.cardano-db-sync system))
        (mkPkgOpt "cardano-db-tool" (cfg.group.pkgs.cardano-db-tool system))
        (mkPkgOpt "cardano-faucet" (cfg.group.pkgs.cardano-faucet system))
        (mkPkgOpt "cardano-node" (cfg.group.pkgs.cardano-node system))
        (mkPkgOpt "cardano-ogmios" (cfg.group.pkgs.cardano-ogmios system))
        (mkPkgOpt "cardano-smash" (cfg.group.pkgs.cardano-smash system))
        (mkPkgOpt "cardano-submit-api" (cfg.group.pkgs.cardano-submit-api system))
        (mkPkgOpt "cardano-tracer" (cfg.group.pkgs.cardano-tracer system))
        (mkPkgOpt "mithril-client-cli" (cfg.group.pkgs.mithril-client-cli system))
        (mkPkgOpt "mithril-signer" (cfg.group.pkgs.mithril-signer system))
        (mkSpecialOpt "cardano-db-sync-pkgs" lib.types.attrs (cfg.group.pkgs.cardano-db-sync-pkgs system))
        (mkSpecialOpt "cardano-metadata-pkgs" lib.types.attrs (cfg.group.pkgs.cardano-metadata-pkgs system))
        (mkSpecialOpt "cardano-node-pkgs" (attrsOf anything) (cfg.group.pkgs.cardano-node-pkgs system))
      ];
    };

    rolesSubmodule = submodule {
      options = {
        isCardanoDensePool = mkBoolOpt;
      };
    };

    gfModules = groupFlake.config.flake.nixosModules;
  in {
    key = ./profile-cardano-node-parts.nix;

    options = {
      # Top level nixos module configuration attr for cardano-parts.
      cardano-parts = mkOption {
        type = mainSubmodule;
      };
    };

    config = {
      # The hosts file is case-insensitive, so switch from camelCase attr name to kebab-case
      networking.hosts = mkIf (gfModules ? ips) (let
        # Prior to "github:hercules-ci/flake-parts/dc3b467eac0fe1436e897d01c35dabe63b4749ea"
        # made on Sept 12th, 2024, the expression:
        #
        #   head gfModules.ips.imports
        #
        # yielded an attrSet with attrName as machine name and
        # attrValue as attrSet of ip type to ip value.  We'll refer to this
        # attrSet as ipInfo for simplicity below.
        #
        # After this commit, the same expression instead returns:
        #
        #  {
        #    imports = [
        #      {
        #        _file = "$NIX_STORE_PATH, via option flake.nixosModules.ips";
        #        imports = [
        #          ipInfo
        #        ];
        #      }
        #    ]
        #  }
        #
        # The same info can be extracted with:
        #
        #   head (head (head gfModules.ips.imports).imports).imports
        #
        # but this is getting rather ugly, so let's use a recursive function
        # instead.
        allIps = let
          flattenImports = m:
            if m ? imports && isList m.imports
            then flattenImports (head m.imports)
            else m;
        in
          flattenImports gfModules.ips;

        hostsList =
          # See hostsList type and description above
          # If hostsList is a list, use it directly
          if isList cfgPerNode.meta.hostsList
          then cfgPerNode.meta.hostsList
          # If hostsList is a string of "all", use all machines, otherwise for "group" use group machines
          else if cfgPerNode.meta.hostsList == "all"
          then attrNames nodes
          else topologyLib.groupMachines nodes;

        genHostsType = type: suffix:
          pipe allIps [
            # Filter empty values
            (filterAttrs (_: v: v.${type} != ""))

            # Filter by hosts
            (filterAttrs (n: _: elem n hostsList))

            # Abort on any duplicated ips across machines in the scoped hosts
            # list. Note that default subnets of default vpcs use overlapping
            # cidr ranges and randomly duplicated privateIpv4 assignment in aws
            # is possible. If a collision is detected, recreate the duplicated
            # resource to remove the collision. Alternatively, opentofu cluster
            # resource provisioning could be modified to use non-default
            # resources at the expense of significant additional complexity.
            (ipAttrs:
              deepSeq (
                let
                  ipList = mapAttrsToList (_: v: v.${type}) ipAttrs;
                in
                  map (ip:
                    if (count (ipCheck: ipCheck == ip) ipList) > 1
                    then
                      abort (
                        "ABORT: ${type} ${ip} has more than one occurrence."
                        + "  Refer to nixosModule.ip-module in the downstream repo."
                        + optionalString (type == "privateIpv4")
                        ("  Duplicated private ipv4 may be due to overlapping cidrs on aws default subnets and vpcs"
                          + " in which case recreating one of the ip duplicated resources will resolve the conflict.")
                      )
                    else null)
                  ipList
              )
              ipAttrs)

            # Abort on any hostname larger than RFC1035 allows
            (ipAttrs:
              deepSeq (
                map (hostName:
                  if (stringLength hostName > 63)
                  then abort "ABORT: ${type} hostname ${hostName} has more than 63 characters and may result in DNS lookup failure."
                  else null)
                (attrNames ipAttrs)
              )
              ipAttrs)

            # Transform attrs into expected networking.hosts list of strings attr values
            (mapAttrs' (n: v: nameValuePair v.${type} ["${n}.${suffix}"]))
          ];
      in
        # Merge ip types together in the hosts file declaration.
        foldl' (acc: e: recursiveUpdate acc e) {} (
          (optional (allIps.${name} ? privateIpv4) (genHostsType "privateIpv4" "private-ipv4"))
          ++ (optional (allIps.${name} ? publicIpv4) (genHostsType "publicIpv4" "public-ipv4"))
          ++ (optional (allIps.${name} ? publicIpv6) (genHostsType "publicIpv6" "public-ipv6"))
        ));

      # Enable deployed machines to be able to resolve the /etc/hosts entries created above in cardano-node topology files
      services.dnsmasq.enable = true;
    };
  });
}
