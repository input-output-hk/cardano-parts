# nixosModule: module-aws-ec2
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.aws.instance
#   config.aws.region
#   config.aws.route53
#
# Tips:
#
{inputs, ...}: {
  flake.nixosModules.module-aws-ec2 = {lib, ...}: let
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
            instance = mkOption {
              type = anything;
            };

            region = mkOption {
              type = str;
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
