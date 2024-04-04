{
  description = "Cardano Parts: nix flake parts for cardano clusters";

  inputs = {
    auth-keys-hub.url = "github:input-output-hk/auth-keys-hub";
    auth-keys-hub.inputs.nixpkgs.follows = "nixpkgs";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena/v0.4.0";
    flake-parts.url = "github:hercules-ci/flake-parts";
    inputs-check.url = "github:input-output-hk/inputs-check";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nix.url = "github:nixos/nix/2.19-maintenance";
    opentofu-registry = {
      url = "github:opentofu/registry";
      flake = false;
    };
    sops-nix.url = "github:Mic92/sops-nix";
    terranix.url = "github:terranix/terranix";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Process compose related
    process-compose-flake.url = "github:Platonic-systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";

    # Cardano related inputs
    capkgs.url = "github:input-output-hk/capkgs";
    empty-flake.url = "github:input-output-hk/empty-flake";
    haskell-nix.url = "github:input-output-hk/haskell.nix";
    iohk-nix.url = "github:input-output-hk/iohk-nix";
    iohk-nix-ng.url = "github:input-output-hk/iohk-nix/node-8.10";

    # TMP:
    cardano-node-810.url = "github:IntersectMBO/cardano-node/sl/node-8.10-cc-testnet";

    # Cardano related inputs required for service config
    # Services offered from the nixosModules of this repo are directly assigned to
    # the flake.cardano-parts.pkgs.special.*-service flakeModule options.
    cardano-db-sync-service = {
      url = "github:IntersectMBO/cardano-db-sync/13.2.0.1";
      flake = false;
    };

    cardano-db-sync-schema = {
      url = "github:IntersectMBO/cardano-db-sync/13.2.0.1";
      flake = false;
    };

    cardano-db-sync-schema-ng = {
      url = "github:IntersectMBO/cardano-db-sync/sancho-4-0-0";
      flake = false;
    };

    cardano-node-service = {
      url = "github:IntersectMBO/cardano-node/8.9.1";
      flake = false;
    };

    cardano-node-service-ng = {
      url = "github:IntersectMBO/cardano-node/8.9.1";
      flake = false;
    };

    cardano-wallet-service = {
      url = "github:cardano-foundation/cardano-wallet/v2024-03-01";
      flake = false;
    };

    cardano-metadata-service = {
      url = "github:input-output-hk/offchain-metadata-tools/ops-1-0-0";
      flake = false;
    };

    # Reduce stackage.nix source download deps
    haskell-nix.inputs.stackage.follows = "empty-flake";
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
