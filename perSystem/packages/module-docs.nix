# perSystem/packages/module-docs.nix
{
  inputs,
  self,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    inherit (pkgs) nixosOptionsDoc runCommand writeText;

    # ---------------------------------------------------------------------------
    # NixOS module docs
    # ---------------------------------------------------------------------------
    # One shared nixosSystem eval. The real upstream service modules are imported
    # directly; a small stub module provides cardano-parts-specific data and stubs
    # for the metadata service (no upstream NixOS module imported).
    # _module.check = false suppresses "option does not exist" errors from config
    # sections that reference options not declared by any imported module.

    # Genesis file stubs — modules that unconditionally call readFile on genesis
    # files in their let-blocks get these toFile paths instead of real store paths.
    byronGenesisStub = builtins.toFile "byron-genesis-stub.json" (builtins.toJSON {
      protocolConsts.protocolMagic = 764824073;
    });
    shelleyGenesisStub = builtins.toFile "shelley-genesis-stub.json" (builtins.toJSON {
      slotsPerKESPeriod = 129600;
      systemStart = "2017-09-23T21:44:51Z";
      epochLength = 432000;
    });

    # Shared cardanoLib stub used by both cardano-parts perNode.lib and
    # services.cardano-node.cardanoNodePackages (the real upstream module).
    cardanoLibStub = {
      environments.mainnet = {
        edgeNodes = [];
        edgePort = 3001;
        useLedgerAfterSlot = -1;
        nodeConfig = {
          ByronGenesisFile = byronGenesisStub;
          ShelleyGenesisFile = shelleyGenesisStub;
          MinNodeVersion = "10.6.0";
          Protocol = "Cardano";
        };
        nodeConfigLegacy = {
          ByronGenesisFile = byronGenesisStub;
          ShelleyGenesisFile = shelleyGenesisStub;
          MinNodeVersion = "10.0.0";
          Protocol = "Cardano";
        };
        dbSyncConfig = {};
      };
      mkEdgeTopology = _: {};
      mkEdgeTopologyP2P = _: {};
    };

    # cardanoNodePackages stub for the real upstream cardano-node-service.nix.
    # That module's cardanoNodePackages option defaults to
    # `pkgs.cardanoNodePackages or (import ../. {...}).cardanoNodePackages`;
    # setting this value in config prevents the import from ever being evaluated.
    cardanoNodePackagesStub = {
      cardano-node = pkgs.hello;
      cardano-tracer = pkgs.hello;
      cardano-submit-api = pkgs.hello;
      cardanoLib = cardanoLibStub;
    };

    nixosDocsEval = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        nodeResources = {
          provider = "aws";
          coreCount = 2;
          cpuCount = 4;
          memMiB = 8192;
          nodeType = "m5ad.large";
          threadsPerCore = 2;
        };
        # Colmena args used by several modules
        nodes = {};
        name = "docs-eval";
        # profile-grafana-alloy requests `self` as a module arg
        inherit self;
      };
      modules = [
        # Real upstream service modules — replace the hand-rolled option stubs.
        "${inputs.cardano-node-service}/nix/nixos/cardano-node-service.nix"
        "${inputs.cardano-tracer-service}/nix/nixos/cardano-tracer-service.nix"
        "${inputs.cardano-db-sync-service}/nix/nixos/cardano-db-sync-service.nix"
        "${inputs.cardano-db-sync-service}/nix/nixos/smash-service.nix"
        # --- Tier 1: no Colmena args, simple deps ---
        self.nixosModules.module-aws-ec2
        self.nixosModules.module-nginx-vhost-exporter
        self.nixosModules.profile-aws-ec2-ephemeral
        self.nixosModules.profile-cardano-postgres
        # --- Tier 2: needs cardano-parts.perNode stubs ---
        self.nixosModules.profile-cardano-node-topology
        # --- Tier 2: cluster.group + opsLib stubs ---
        self.nixosModules.profile-mithril-relay
        self.nixosModules.profile-cardano-custom-metrics
        self.nixosModules.profile-tcpdump
        self.nixosModules.profile-blockperf
        # profile-grafana-agent is legacy (replaced by alloy) — not documented
        self.nixosModules.profile-grafana-alloy
        # --- Tier 3: imports other cardano-parts nixosModules ---
        self.nixosModules.profile-cardano-node-group
        self.nixosModules.role-block-producer
        self.nixosModules.profile-cardano-db-sync
        self.nixosModules.profile-cardano-db-sync-snapshots
        self.nixosModules.service-cardano-faucet
        self.nixosModules.profile-cardano-faucet
        self.nixosModules.profile-cardano-webserver
        self.nixosModules.profile-cardano-smash
        self.nixosModules.profile-cardano-metadata

        # Stub module — cardano-parts-specific data + metadata service stubs
        ({
          lib,
          pkgs,
          ...
        }: {
          options = {
            # profile-cardano-node-topology deps (and others using perNode)
            cardano-parts = lib.mkOption {
              type = lib.types.anything;
              default = {
                cluster.group = {
                  # groupName and groupFlake used by blockperf, tcpdump, grafana-agent, grafana-alloy
                  groupName = "docs-group";
                  groupFlake.self.outPath = "/dev/null";
                  meta = {
                    environmentName = "mainnet";
                    # domain used by service-cardano-faucet, profile-cardano-webserver,
                    # profile-cardano-smash, profile-cardano-metadata
                    domain = "example.com";
                  };
                };
                perNode = {
                  lib = {
                    cardanoLib = cardanoLibStub;
                    topologyLib = {
                      topoList = _: [];
                      topoInfixFiltered = _: [];
                      topoSimple = _: [];
                      topoSimpleMax = _: [];
                      p2pEdgeNodes = _: [];
                    };
                  };
                  # Prometheus port / address metadata used by grafana-agent, grafana-alloy, custom-metrics
                  meta = {
                    cardanoDbSyncPrometheusExporterPort = 8080;
                    cardanoNodePrometheusExporterPort = 12798;
                    cardanoNodePort = 3001;
                    hostAddr = "0.0.0.0";
                    # hostAddrIpv6 used by profile-cardano-node-group
                    hostAddrIpv6 = "::";
                    # nodeId used by profile-cardano-node-group
                    nodeId = 0;
                    # cardanoSmashDelistedPools used by profile-cardano-smash
                    cardanoSmashDelistedPools = [];
                  };
                  # Package stubs used by various modules
                  pkgs = {
                    blockperf = pkgs.hello;
                    cardano-cli = pkgs.hello;
                    cardano-node = pkgs.hello;
                    cardano-node-pkgs = cardanoNodePackagesStub;
                    cardano-tracer = pkgs.hello;
                    mithril-client-cli = pkgs.hello;
                    mithril-signer = pkgs.hello;
                    cardano-db-sync = pkgs.hello;
                    cardano-db-sync-pkgs = {};
                    cardano-db-tool = pkgs.hello;
                    cardano-faucet = pkgs.hello;
                    cardano-smash = pkgs.hello;
                    cardano-metadata-pkgs = {
                      metadata-server = pkgs.hello;
                      metadata-sync = pkgs.hello;
                      metadata-webhook = pkgs.hello;
                    };
                  };
                  # roles used by role-block-producer
                  roles.isCardanoDensePool = false;
                };
              };
            };

            # metadata service stubs for profile-cardano-metadata config section
            # (no upstream NixOS module imported for the metadata service)
            services = {
              metadata-server = lib.mkOption {
                type = lib.types.anything;
                default = {
                  user = "metadata";
                  postgres = {
                    database = "metadata";
                    user = "metadata";
                    socketdir = "/run/postgresql";
                    port = 5432;
                    table = "";
                    numConnections = 4;
                  };
                };
              };
              metadata-webhook = lib.mkOption {
                type = lib.types.anything;
                default.user = "metadata-webhook";
              };
              metadata-sync = lib.mkOption {
                type = lib.types.anything;
                default.user = "metadata-sync";
              };
            };

            # sops stub: profile-tcpdump's environmentFile default reads
            # config.sops.secrets.tcpdump.path when useSopsSecrets = true
            sops = lib.mkOption {
              type = lib.types.anything;
              default = {
                secrets.tcpdump.path = "/run/secrets/tcpdump";
              };
            };
          };

          config = {
            _module.check = false;
            system.stateVersion = "24.11";
            fileSystems."/" = {
              device = "/dev/null";
              fsType = "tmpfs";
            };
            boot.loader.grub.device = "nodev";
            networking.hostName = "docs-eval";
            # profile-blockperf.enable defaults to true; its config section calls
            # mkSopsSecret with keyName = cfg.clientCert/clientKey/amazonCa which
            # default to null, causing "cannot coerce null to a string".
            # Setting enable = false skips the config body, leaving option docs intact.
            # module-aws-ec2 declares aws.{instance,region,route53} with no defaults
            aws = {
              instance = {
                instance_type = "m5.large";
                count = 1;
              };
              region = "eu-central-1";
            };
            services = {
              # profile-blockperf.enable defaults to true; its config section calls
              # mkSopsSecret with keyName = cfg.clientCert/clientKey/amazonCa which
              # default to null, causing "cannot coerce null to a string".
              # Setting enable = false skips the config body, leaving option docs intact.
              blockperf.enable = false;
              # profile-tcpdump.environmentFile default accesses config.sops.secrets.tcpdump.path
              # when useSopsSecrets = true, but the anything-type sops stub doesn't reliably
              # preserve the `path` attribute through the merge with mkSopsSecret's output.
              # Disabling useSopsSecrets makes the default evaluate to null instead.
              tcpdump.useSopsSecrets = false;
              cardano-node = {
                # role-block-producer: disable sops secrets to avoid mkSopsSecret with
                # real paths that don't exist under /dev/null/secrets/...
                useSopsSecrets = false;
                # Provide cardanoNodePackages so the upstream module's default
                # `pkgs.cardanoNodePackages or (import ../. {...}).cardanoNodePackages`
                # is never evaluated.
                cardanoNodePackages = cardanoNodePackagesStub;
              };
              # profile-cardano-db-sync-snapshots: same reason
              cardano-db-sync-snapshots.useSopsSecrets = false;
              # profile-cardano-metadata: same reason
              cardano-metadata.useSopsSecrets = false;
              # profile-cardano-webserver: vhostsDir default is
              # "${groupFlake.self.outPath}/static" = "/dev/null/static" which doesn't
              # exist as a directory.  Point to this file's own directory (perSystem/packages)
              # which has only .nix files — no "directory" or "symlink" entries →
              # vhostsDirList = [] → no nginx vhosts crash.
              cardano-webserver.vhostsDir = toString ./.;
            };
          };
        })
      ];
    };

    # Option namespaces defined by cardano-parts NixOS modules.
    # Extend this list as more modules are added.
    cardanoPartsPrefixes = [
      # Tier 1
      "aws."
      "services.nginx-vhost-exporter."
      "services.aws.ec2.ephemeral."
      "services.cardano-postgres."
      # Tier 2
      "services.cardano-node-topology."
      "services.mithril-relay."
      "services.cardano-custom-metrics."
      "services.tcpdump."
      "services.blockperf."
      # services.grafana-agent is legacy; not documented
      "services.alloy."
      # Tier 3 — profile-cardano-node-group adds sub-options to services.cardano-node
      # and declares the services.mithril-client namespace
      "services.cardano-node.totalCpuCount"
      "services.cardano-node.totalMaxHeapSizeMiB"
      "services.cardano-node.shareNodeSocket"
      "services.mithril-client."
      # Tier 3 — role-block-producer adds a sub-option to services.cardano-node
      # and declares the services.mithril-signer namespace
      "services.cardano-node.useSopsSecrets"
      "services.mithril-signer."
      # Tier 3 — profile-cardano-db-sync adds sub-options to services.cardano-db-sync
      "services.cardano-db-sync.additionalDbUsers"
      "services.cardano-db-sync.nodeRamAvailableMiB"
      "services.cardano-db-sync.postgresRamAvailableMiB"
      # Tier 3 — dedicated namespaces
      "services.cardano-db-sync-snapshots."
      "services.cardano-faucet."
      "services.cardano-webserver."
      "services.cardano-smash."
      "services.cardano-metadata."
    ];

    isDocumented = name:
      builtins.any (prefix: lib.hasPrefix prefix name) cardanoPartsPrefixes;

    nixosDoc = nixosOptionsDoc {
      inherit (nixosDocsEval) options;
      transformOptions = opt:
        if isDocumented opt.name
        then opt // {declarations = [];}
        else
          opt
          // {
            visible = false;
            internal = true;
          };
      warningsAreErrors = false;
    };

    # ---------------------------------------------------------------------------
    # Flake module docs
    # ---------------------------------------------------------------------------
    # Build a standalone evalModules with only the four cardano-parts flake
    # modules. This avoids touching flake-parts internals (which would trigger
    # perSystem package evaluation without a system context).
    #
    # In flake-parts, topLevel.options.flake is a single option OBJECT (not a
    # nested attrset), so `topLevel.options.flake.cardano-parts` does not exist
    # directly. In a plain lib.evalModules, options ARE a nested attrset, so
    # `flakeDocEval.options.flake.cardano-parts` works correctly.
    #
    # Stubs:
    #   withSystem = _: _: null   -- cluster.nix/pkgs.nix; every default that
    #                                calls withSystem has defaultText, so the
    #                                stub function is never actually invoked
    #   flake-parts-lib.mkPerSystemOption -- pkgs.nix uses this; stub returns an
    #                                        anything-typed option (not doc'd here)
    #   flake.nixosModules = {}   -- cluster.nix `addressType` default checks
    #                                `flake.config.flake.nixosModules ? ips`
    # Note: self.flakeModules.pkgs is a set (importApply already applied
    # localFlake = self); used directly without re-applying localFlake.
    flakeDocEval = inputs.nixpkgs.lib.evalModules {
      specialArgs = {
        withSystem = _: _: null;
        flake-parts-lib = {
          mkPerSystemOption = _:
            lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
        };
      };
      modules = [
        ({lib, ...}: {
          config._module.check = false;
          options.flake.nixosModules = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
        })
        self.flakeModules.cluster
        self.flakeModules.pkgs
        self.flakeModules.lib
        self.flakeModules.aws
      ];
    };

    flakeCardanoPartsSubOpts = flakeDocEval.options.flake.cardano-parts.type.getSubOptions ["flake" "cardano-parts"];

    flakeDoc = nixosOptionsDoc {
      options = {
        "flake.cardano-parts" = flakeCardanoPartsSubOpts;
      };
      transformOptions = opt:
        opt
        // {declarations = [];}
        // lib.optionalAttrs (!(opt ? defaultText)) {defaultText = lib.literalMD "*see source*";};
      warningsAreErrors = false;
    };

    # ---------------------------------------------------------------------------
    # Headers
    # ---------------------------------------------------------------------------
    flakeHeader = writeText "flake-header.md" ''
      # Flake Module Options

      Options defined by cardano-parts flakeModules, configured in the
      consuming repository's flake-parts modules.

    '';

    nixosHeader = writeText "nixos-header.md" ''
      # NixOS Module Options

      Options defined by cardano-parts NixOS modules, configured
      per-machine in NixOS configurations.

    '';
  in {
    packages = {
      module-docs-nixos = runCommand "module-docs-nixos" {} ''
        mkdir -p $out
        cat ${nixosHeader} ${nixosDoc.optionsCommonMark} > $out/nixos-options.md
      '';

      module-docs-flake = runCommand "module-docs-flake" {} ''
        mkdir -p $out
        cat ${flakeHeader} ${flakeDoc.optionsCommonMark} > $out/flake-options.md
      '';

      module-docs = runCommand "module-docs" {} ''
        mkdir -p $out
        cat ${nixosHeader} ${nixosDoc.optionsCommonMark} > $out/nixos-options.md
        cat ${flakeHeader} ${flakeDoc.optionsCommonMark} > $out/flake-options.md
      '';
    };
  };
}
