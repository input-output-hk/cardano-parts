{
  description = "Cardano Parts: nix flake parts for cardano clusters";

  inputs = {
    auth-keys-hub.url = "github:input-output-hk/auth-keys-hub";
    auth-keys-hub.inputs.nixpkgs.follows = "nixpkgs";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena/v0.4.0";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    sops-nix.url = "github:Mic92/sops-nix";
    terraform-providers.url = "github:nix-community/nixpkgs-terraform-providers-bin";
    terranix.url = "github:terranix/terranix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Cardano related inputs
    # TODO: Address large and likely unneeded stackage.nix ref in each haskell.nix input adding ~320 MB source deps
    cardano-cli-ng.url = "github:input-output-hk/cardano-cli/cardano-cli-8.5.0.0-nix";
    cardano-db-sync.url = "github:input-output-hk/cardano-db-sync/13.1.1.3";
    # cardano-faucet.url = "github:input-output-hk/cardano-faucet";
    cardano-node-ng.url = "github:input-output-hk/cardano-node/8.2.1-pre";
    cardano-node.url = "github:input-output-hk/cardano-node/8.1.2";
    cardano-wallet.url = "github:cardano-foundation/cardano-wallet/v2023-07-18";
    haskellNix.url = "github:input-output-hk/haskell.nix";
    iohkNix.url = "github:input-output-hk/iohk-nix";
    offchain-metadata-tools.url = "github:input-output-hk/offchain-metadata-tools/feat-add-password-to-db-conn-string";
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

      passLocalFlake = flakeModuleFile:
        importApply flakeModuleFile {
          inherit withSystem;
          localFlake = self;
        };

      fmCluster = ./flakeModules/cluster.nix;
      fmPkgs = passLocalFlake ./flakeModules/pkgs.nix;
      fmShell = passLocalFlake ./flakeModules/shell.nix;
    in {
      imports =
        recursiveImports [./flake ./perSystem]
        # Special imports
        ++ [fmCluster fmPkgs fmShell];

      systems = ["x86_64-linux"];

      flake = {
        flakeModules = {
          cluster = fmCluster;
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
