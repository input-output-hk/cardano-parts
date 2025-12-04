{
  description = "Cardano Parts: nix flake parts for cardano clusters";

  inputs = {
    auth-keys-hub = {
      url = "github:input-output-hk/auth-keys-hub";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    inputs-check = {
      url = "github:input-output-hk/inputs-check";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nix.url = "github:nixos/nix/2.29-maintenance";

    opentofu-registry = {
      url = "github:opentofu/registry";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    terranix = {
      url = "github:terranix/terranix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Process compose related
    process-compose-flake.url = "github:Platonic-systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";

    # Cardano related inputs
    capkgs.url = "github:input-output-hk/capkgs";
    iohk-nix.url = "github:input-output-hk/iohk-nix";
    iohk-nix-ng.url = "github:input-output-hk/iohk-nix";
    # iohk-nix-ng.url = "path:/home/jlotoski/work/iohk/iohk-nix-wt/jl/10.6.0-pre-updates";

    # Until blockperf detail fix is merged to master upstream
    blockperf.url = "github:johnalotoski/blockperf/jl/fix-detail";

    # For tmp local testing pins
    # cardano-faucet.url = "github:input-output-hk/cardano-faucet/jl/node-9.2";
    # cardano-faucet.url = "path:/home/jlotoski/work/iohk/cardano-faucet-wt/jl/node-9.2";

    # Cardano-db-sync schema input pins, which must match the
    # versioning of the release and pre-release (-ng) dbsync
    # definitions found in flakeModule/pkgs.nix.
    cardano-db-sync-schema = {
      url = "github:IntersectMBO/cardano-db-sync/13.6.0.5";
      flake = false;
    };

    cardano-db-sync-schema-ng = {
      url = "github:IntersectMBO/cardano-db-sync/13.6.0.6";
      flake = false;
    };

    # Cardano inputs required for nixos services follow. These services
    # are assigned to the flake.cardano-parts.pkgs.special.*-service
    # flakeModule options and do not necessarily reflect the software
    # versions running on those nixos services.
    cardano-db-sync-service = {
      url = "github:IntersectMBO/cardano-db-sync/13.6.0.5";
      flake = false;
    };

    cardano-db-sync-service-ng = {
      url = "github:IntersectMBO/cardano-db-sync/13.6.0.6";
      flake = false;
    };

    cardano-node-service = {
      url = "github:IntersectMBO/cardano-node/f11e0f303ddf3e5b8975daf72ceaa522ddb98426";
      flake = false;
    };

    cardano-node-service-ng = {
      url = "github:IntersectMBO/cardano-node/10.6.0";
      flake = false;
    };

    cardano-metadata-service = {
      url = "github:input-output-hk/offchain-metadata-tools/ops-1-0-0";
      flake = false;
    };

    cardano-ogmios-service = {
      url = "github:input-output-hk/cardano-ogmios/ogmios-6-3-0";
      flake = false;
    };

    blockfrost-platform-service = {
      url = "github:blockfrost/blockfrost-platform";
      flake = false;
    };

    cardano-submit-api-service = {
      url = "github:IntersectMBO/cardano-node/f11e0f303ddf3e5b8975daf72ceaa522ddb98426";
      flake = false;
    };

    cardano-submit-api-service-ng = {
      url = "github:IntersectMBO/cardano-node/10.6.0";
      flake = false;
    };

    cardano-tracer-service = {
      url = "github:IntersectMBO/cardano-node/f11e0f303ddf3e5b8975daf72ceaa522ddb98426";
      flake = false;
    };

    cardano-tracer-service-ng = {
      url = "github:IntersectMBO/cardano-node/10.6.0";
      flake = false;
    };

    cardano-wallet-service = {
      url = "github:cardano-foundation/cardano-wallet/v2025-03-31";
      flake = false;
    };
  };

  outputs = inputs: let
    inherit ((import ./flake/lib.nix {inherit inputs;}).flake.lib) recursiveImports;
  in
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({
      flake-parts-lib,
      self,
      withSystem,
      ...
    }: let
      inherit (flake-parts-lib) importApply;

      passLocalFlake = flakeModuleFile: extraCfg:
        importApply flakeModuleFile ({
            localFlake = self;
          }
          // extraCfg);

      fmAws = ./flakeModules/aws.nix;
      fmCluster = ./flakeModules/cluster.nix;
      fmEntrypoints = ./flakeModules/entrypoints.nix;
      fmJobs = passLocalFlake ./flakeModules/jobs.nix {};
      fmLib = ./flakeModules/lib.nix;
      fmPkgs = passLocalFlake ./flakeModules/pkgs.nix {};
      fmProcessCompose = passLocalFlake ./flakeModules/process-compose.nix {};
      fmShell = passLocalFlake ./flakeModules/shell.nix {inherit withSystem;};
    in {
      imports =
        recursiveImports [./flake ./perSystem]
        # Special imports
        ++ [
          fmAws
          fmCluster
          fmEntrypoints
          fmJobs
          fmLib
          fmPkgs
          fmShell
          inputs.inputs-check.flakeModule
          inputs.process-compose-flake.flakeModule
        ];

      systems = ["x86_64-linux"];

      flake = {
        flakeModules = {
          aws = fmAws;
          cluster = fmCluster;
          entrypoints = fmEntrypoints;
          jobs = fmJobs;
          lib = fmLib;
          pkgs = fmPkgs;
          process-compose = fmProcessCompose;
          shell = fmShell;
        };
      };

      debug = true;
    });

  nixConfig = {
    extra-substituters = ["https://cache.iog.io"];
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
    allow-import-from-derivation = "true";
  };
}
