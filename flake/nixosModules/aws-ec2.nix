{inputs, ...}: {
  flake.nixosModules.aws-ec2 = {lib, ...}: let
    inherit (lib) mkDefault mkOption types;
    inherit (types) anything nullOr str submodule;
  in {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
    ];

    options = {
      aws = mkOption {
        default = null;
        type = types.nullOr (submodule {
          options = {
            region = mkOption {
              type = str;
            };

            instance = mkOption {
              type = anything;
            };

            route53 = mkOption {
              default = null;
              type = nullOr anything;
            };
          };

          config = {
            instance.count = mkDefault 1;
          };
        });
      };
    };
  };
}
