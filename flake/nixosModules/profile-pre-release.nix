# nixosModule: profile-pre-release
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
flake @ {moduleWithSystem, ...}: {
  flake.nixosModules.profile-pre-release = moduleWithSystem ({
    config,
    system,
  }: nixos: let
    inherit (groupCfg) groupFlake;

    groupCfg = nixos.config.cardano-parts.cluster.group;
  in {
    cardano-parts.perNode = {
      lib.cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
      pkgs = {
        cardano-cli = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node-ng);
        cardano-node = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node-ng);
        cardano-submit-api = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api-ng);
        cardano-node-pkgs = groupFlake.config.flake.cardano-parts.pkgs.special.cardano-node-pkgs-ng system;
      };
    };
  });
}
