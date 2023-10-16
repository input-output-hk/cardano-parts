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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nix.url = "github:nixos/nix/2.17-maintenance";
    sops-nix.url = "github:Mic92/sops-nix";
    terraform-providers.url = "github:nix-community/nixpkgs-terraform-providers-bin";
    terranix.url = "github:terranix/terranix";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Cardano related inputs
    capkgs.url = "github:input-output-hk/capkgs";
    empty-flake.url = "github:input-output-hk/empty-flake";
    haskell-nix.url = "github:input-output-hk/haskell.nix";
    iohk-nix.url = "github:input-output-hk/iohk-nix/2f3760f135616ebc477d3ed74eba9b63c22f83a0";
    iohk-nix-ng.url = "github:input-output-hk/iohk-nix";

    # Cardano related inputs required for service config
    # Services offered from the nixosModules of this repo are directly assigned to
    # the flake.cardano-parts.pkgs.special.*-service flakeModule options.
    cardano-db-sync-service = {
      url = "github:input-output-hk/cardano-db-sync/13.1.1.3";
      flake = false;
    };

    cardano-db-sync-schema = {
      url = "github:input-output-hk/cardano-db-sync/13.1.1.3";
      flake = false;
    };

    cardano-db-sync-schema-ng = {
      url = "github:input-output-hk/cardano-db-sync/sancho-2-0-0";
      flake = false;
    };

    cardano-node-service = {
      url = "github:input-output-hk/cardano-node/8.1.2";
      flake = false;
    };

    cardano-wallet-service = {
      url = "github:cardano-foundation/cardano-wallet/v2023-07-18";
      flake = false;
    };

    offchain-metadata-tools-service = {
      url = "github:input-output-hk/offchain-metadata-tools/feat-add-password-to-db-conn-string";
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
