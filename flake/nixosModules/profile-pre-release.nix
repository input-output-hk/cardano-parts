# nixosModule: profile-pre-release
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
flake @ {moduleWithSystem, ...}: {
  flake.nixosModules.profile-pre-release = moduleWithSystem ({system}: nixos: let
    inherit (groupCfg) groupFlake;

    groupCfg = nixos.config.cardano-parts.cluster.group;
  in {
    key = ./profile-pre-release.nix;

    config = {
      cardano-parts.perNode = {
        lib.cardanoLib = flake.config.flake.cardano-parts.pkgs.special.cardanoLibNg system;
        pkgs = {
          cardano-cli = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-cli-ng);
          cardano-db-sync = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-sync-ng);
          cardano-db-sync-pkgs = groupFlake.config.flake.cardano-parts.pkgs.special.cardano-db-sync-pkgs-ng system;
          cardano-db-tool = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-db-tool-ng);
          cardano-faucet = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-faucet-ng);
          cardano-node = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-node-ng);
          cardano-node-pkgs = groupFlake.config.flake.cardano-parts.pkgs.special.cardano-node-pkgs-ng system;
          cardano-smash = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-smash-ng);
          cardano-submit-api = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-submit-api-ng);
          cardano-tracer = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.cardano-tracer-ng);
          mithril-client-cli = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.mithril-client-cli-ng);
          mithril-signer = groupFlake.withSystem system ({config, ...}: config.cardano-parts.pkgs.mithril-signer-ng);
        };
      };
    };
  });
}
