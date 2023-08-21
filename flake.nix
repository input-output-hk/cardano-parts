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
    sops-nix.url = "github:Mic92/sops-nix";
    terraform-providers.url = "github:nix-community/nixpkgs-terraform-providers-bin";
    terranix.url = "github:terranix/terranix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Cardano related inputs
    cardano-cli-ng.url = "github:input-output-hk/cardano-cli/cardano-cli-8.5.0.0-nix";
    cardano-db-sync.url = "github:input-output-hk/cardano-db-sync/13.1.1.3";
    cardano-faucet.url = "github:input-output-hk/cardano-faucet";
    cardano-node-ng.url = "github:input-output-hk/cardano-node/8.2.1-pre";
    cardano-node.url = "github:input-output-hk/cardano-node/8.1.2";
    cardano-wallet.url = "github:cardano-foundation/cardano-wallet/v2023-07-18";
    empty-flake.url = "github:input-output-hk/empty-flake";
    haskell-nix.url = "github:input-output-hk/haskell.nix";
    iohk-nix.url = "github:input-output-hk/iohk-nix";
    offchain-metadata-tools.url = "github:input-output-hk/offchain-metadata-tools/feat-add-password-to-db-conn-string";

    # Reduce stackage.nix large download source deps for any haskell.nix pins found in `nix flake metadata`
    # Residual nested stackage refs can be addressed once updating transitive inputs are allowed:
    #   https://github.com/NixOS/nix/issues/5790
    #   https://github.com/NixOS/nix/pull/8819
    # Until then, stackage nested deps add about 2 GB d/l on first direnv load
    haskell-nix.inputs.stackage.follows = "empty-flake";

    # By setting all haskell.nix pins to this flake's haskell.nix pin, all stackage.nix refs are set to ~0 size,
    # all hackage.nix refs will be shared ~(50 MB per ref), reducing closure size significantly
    cardano-cli-ng.inputs.haskellNix.follows = "haskell-nix";
    cardano-cli-ng.inputs.nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
    cardano-db-sync.inputs.haskellNix.follows = "haskell-nix";
    cardano-db-sync.inputs.nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
    cardano-faucet.inputs.haskellNix.follows = "haskell-nix";
    cardano-faucet.inputs.nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
    cardano-node-ng.inputs.haskellNix.follows = "haskell-nix";
    cardano-node-ng.inputs.nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
    cardano-node.inputs.haskellNix.follows = "haskell-nix";
    cardano-node.inputs.nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
    cardano-wallet.inputs.haskellNix.follows = "haskell-nix";
    cardano-wallet.inputs.nixpkgs.follows = "haskell-nix/nixpkgs-unstable";
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

      fmCluster = ./flakeModules/cluster.nix;
      fmEntrypoints = ./flakeModules/entrypoints.nix;
      fmPkgs = passLocalFlake ./flakeModules/pkgs.nix {};
      fmShell = passLocalFlake ./flakeModules/shell.nix {inherit withSystem;};
    in {
      imports =
        recursiveImports [./flake ./perSystem]
        # Special imports
        ++ [
          fmCluster
          fmEntrypoints
          fmPkgs
          fmShell
          inputs.inputs-check.flakeModule
        ];

      systems = ["x86_64-linux"];

      flake = {
        flakeModules = {
          cluster = fmCluster;
          entrypoints = fmEntrypoints;
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
