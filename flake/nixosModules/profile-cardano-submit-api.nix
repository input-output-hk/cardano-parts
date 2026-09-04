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
#   * It waits for the node socket on pre-start and bounds restarts so persistent failures alert
#   * The upstream cardano-submit-api nixos service module should still be imported separately
{moduleWithSystem, ...}: {
  flake.nixosModules.profile-cardano-submit-api = moduleWithSystem (_: nixos @ {
    pkgs,
    lib,
    ...
  }: let
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

      systemd.services.cardano-submit-api = {
        # Bounded restart policy: retry on failure, but if startup keeps failing
        # (e.g. an extended node outage or a genuine misconfiguration) let the
        # start-limit trip so the unit enters `failed` and alerting fires rather
        # than restarting silently forever. With the default StartLimitBurst of
        # 5 and RestartSec 30s, ~5 failed (re)starts within the interval below
        # surface as a failed unit.
        startLimitIntervalSec = 1800;
        serviceConfig = {
          Restart = "always";
          RestartSec = "30s";

          # Allow for delayed node startup (e.g. ledger replay) while still
          # bounding how long a single start may hang on the socket waits.
          TimeoutStartSec = "300s";

          # Gate startup on the node socket existing and being group-writeable
          # (cardano-node creates and chmods it asynchronously after it starts).
          # This avoids crash-looping before the socket is ready; bounded by
          # TimeoutStartSec above.
          ExecStartPre = lib.getExe (pkgs.writeShellApplication {
            name = "cardano-submit-api-wait-for-node-socket";
            runtimeInputs = with pkgs; [coreutils findutils];
            text = ''
              socket="${nodeCfg.socketPath 0}"

              # Wait until the node socket exists.
              while [ ! -S "$socket" ]; do
                echo "Waiting for cardano node socket at $socket ..."
                sleep 10
              done

              # Wait until the node socket is group-writeable (cardano-node
              # chmods it after start).
              while [ "$(find "$socket" -type s -perm -g+w)" != "$socket" ]; do
                echo "Waiting for cardano node socket group write permission at $socket ..."
                sleep 10
              done
            '';
          });
        };
      };
    };
  });
}
