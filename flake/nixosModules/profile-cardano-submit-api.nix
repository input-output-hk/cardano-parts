# nixosModule: profile-cardano-submit-api
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   (none beyond the upstream cardano-submit-api service options)
#
# Tips:
#   * This is a cardano-submit-api profile add-on to the upstream cardano-submit-api nixos service module
#   * This module wires submit-api to the cluster's environment name, node packages and node socket
#   * It bounds restarts so persistent service failures alert
#   * The upstream cardano-submit-api nixos service module should still be imported separately
{moduleWithSystem, ...}: {
  flake.nixosModules.profile-cardano-submit-api = moduleWithSystem (_: nixos: let
    inherit (groupCfg.meta) environmentName;
    inherit (perNodeCfg.pkgs) cardano-node-pkgs cardano-submit-api;

    groupCfg = nixos.config.cardano-parts.cluster.group;
    nodeCfg = nixos.config.services.cardano-node;
    perNodeCfg = nixos.config.cardano-parts.perNode;
  in {
    key = ./profile-cardano-submit-api.nix;

    config = {
      services = {
        # Share the node socket so the submit-api (a DynamicUser placed in the
        # cardano-node group below) can reach CARDANO_NODE_SOCKET_PATH.
        cardano-node.shareNodeSocket = true;

        cardano-submit-api = {
          enable = true;
          cardanoNodePackages = cardano-node-pkgs;
          # config defaults to cardanoLib.defaultSubmitApiConfig
          group = "cardano-node";
          network = environmentName;
          package = cardano-submit-api;
          socketPath = nodeCfg.socketPath 0;
        };
      };

      # Submit-api listens without the node and opens its socket per submission,
      # so startup does not need to wait for node replay or socket permissions.
      systemd.services.cardano-submit-api = {
        # Bounded restart policy: retry on failure, but if startup keeps failing
        # (e.g. a genuine misconfiguration) let the
        # start-limit trip so the unit enters `failed` and alerting fires rather
        # than restarting silently forever. With the default StartLimitBurst of
        # 5 and RestartSec 30s, ~5 failed (re)starts within the interval below
        # surface as a failed unit.
        startLimitIntervalSec = 1800;
        serviceConfig = {
          Restart = "always";
          RestartSec = "30s";
        };
      };
    };
  });
}
