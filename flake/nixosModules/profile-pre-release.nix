# nixosModule: profile-pre-release
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
{
  config,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.profile-pre-release = moduleWithSystem ({system}: {
    cardano-parts.perNode = {
      lib.cardanoLib = config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
      pkgs.cardano-node-pkgs = config.flake.cardano-parts.pkgs.special.cardano-node-pkgs-ng system;
    };
  });
}
