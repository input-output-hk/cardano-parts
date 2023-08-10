{
  description = "Cardano Parts: nix flake parts for cardano clusters";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({...}: {
      imports = [
        ./flake
        ./perSystem
        ./flakeModules/shell.nix
      ];

      systems = ["x86_64-linux"];

      flake = rec {
        flakeModule = flakeModules.default;
        flakeModules = rec {
          default = shell;
          shell = ./flakeModules/shell.nix;
        };
      };

      # debug = true;
    });

  nixConfig = {
    extra-substituters = ["https://cache.iog.io"];
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
    allow-import-from-derivation = "true";
  };
}
