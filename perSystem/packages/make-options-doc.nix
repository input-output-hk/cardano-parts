flake @ {importApply, ...}: {
  perSystem = {
    inputs',
    lib,
    pkgs,
    system,
    config,
    ...
  }:
    with lib; let
      inherit (inputs'.nixpkgs-unstable.legacyPackages) nixosOptionsDoc;

      evalFlakeModules = evalModules {
        modules = [
          # Disable standard module args documentation.
          {options._module.args = mkOption {internal = true;};}

          # Provide a default description for flake.cardano-parts as the flakeModule
          # files can't declare this in multiple places without option collision.
          {
            options.flake.cardano-parts =
              mkOption {description = "Cardano-parts top-level flakeModule.";};
          }

          # flakeModules to compile options for
          ../../flakeModules/aws.nix

          {
            imports = [
              (flake.flake-parts-lib.importApply ../../flakeModules/cluster.nix {
                inherit (flake) withSystem lib config self;
                localFlake = flake.self;
              })
            ];
          }
          # (import ../../flakeModules/cluster.nix {inherit (flake) withSystem lib config self inputs options;})
          # ../../flakeModules/entrypoints.nix
          # (import ../../flakeModules/jobs.nix {localFlake = flake;})
          ../../flakeModules/lib.nix
          # ../../flakeModules/pkgs.nix
          # ../../flakeModules/shell.nix
          # {
          #   imports = [
          #     (flake.flake-parts-lib.importApply ../../flakeModules/shell.nix {
          #       inherit (flake) withSystem;
          #       localFlake = flake.self;
          #     })
          #   ];
          # }
        ];
      };

      evalNixosModules = evalModules {
        modules = [
          # Disable standard module args documentation
          {options._module.args = mkOption {internal = true;};}
          # ../../flake/nixosModules/module-aws-ec2.nix
          # ../../flake/nixosModules/module-cardano-block-producer.nix
          # ../../flake/nixosModules/module-cardano-parts.nix
        ];
      };

      flakeModulesOptionsDoc = nixosOptionsDoc {
        inherit (evalFlakeModules) options;
      };

      nixosModulesOptionsDoc = nixosOptionsDoc {
        inherit (evalNixosModules) options;
      };
    in {
      packages.make-options-doc = pkgs.runCommand "generate-options-docs" {} ''
        mkdir -p $out
        cat ${flakeModulesOptionsDoc.optionsCommonMark} >> $out/flakeModule-options.md
        cat ${nixosModulesOptionsDoc.optionsCommonMark} >> $out/nixosModule-options.md
      '';
    };
}
