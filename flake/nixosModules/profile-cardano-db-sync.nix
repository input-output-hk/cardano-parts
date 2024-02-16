# nixosModule: profile-cardano-db-sync
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-db-sync.additionalDbUsers
#   config.services.cardano-db-sync.nodeRamAvailableMiB
#   config.services.cardano-db-sync.postgresRamAvailableMiB
#
# Tips:
#   * This is a cardano-db-sync profile add-on to the upstream cardano-db-sync nixos service module
#   * This module assists with configuring multiple local db-sync consumers
#   * The upstream cardano-db-sync nixos service module should still be imported separately
{moduleWithSystem, ...}: {
  flake.nixosModules.profile-cardano-db-sync = moduleWithSystem ({config, ...}: nixos @ {
    lib,
    name,
    nodeResources,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) float ints listOf oneOf str;
      inherit (nodeResources) memMiB;

      inherit (groupCfg.meta) environmentName;
      inherit (perNodeCfg.lib.cardanoLib) environments;
      inherit (perNodeCfg.meta) cardanoDbSyncPrometheusExporterPort;
      inherit (perNodeCfg.pkgs) cardano-db-sync cardano-db-sync-pkgs cardano-db-tool;

      groupCfg = nixos.config.cardano-parts.cluster.group;
      nodeCfg = nixos.config.services.cardano-node;
      perNodeCfg = nixos.config.cardano-parts.perNode;

      # Required since db-sync still requires legacy byron application parameters as of 13.1.1.3.
      # Issue: https://github.com/IntersectMBO/cardano-db-sync/issues/1473
      #
      environmentConfig = environments.${environmentName}.nodeConfig;

      cfg = nixos.config.services.cardano-db-sync;
    in {
      options = {
        services.cardano-db-sync = {
          additionalDbUsers = mkOption {
            description = "Additional database users for cexplorer database";
            type = listOf str;
            default = [];
          };

          nodeRamAvailableMiB = mkOption {
            description = "The default RAM available for node max heap size on the machine in MiB.";
            type = oneOf [ints.positive float];
            default = memMiB * 0.20;
          };

          postgresRamAvailableMiB = mkOption {
            description = "The default RAM available for postgresql on the machine in MiB.";
            type = oneOf [ints.positive float];
            default = memMiB * 0.70;
          };
        };
      };

      config = {
        environment.systemPackages = [cardano-db-tool];

        services.postgresql = {
          ensureDatabases = ["cexplorer"];
          ensureUsers = [
            {
              name = "cexplorer";
              ensureDBOwnership = true;
            }
          ];

          identMap = ''
              explorer-users postgres postgres
            ${concatMapStrings (user: ''
              explorer-users ${user} cexplorer
            '') (["root" "cardano-db-sync"] ++ cfg.additionalDbUsers)}'';

          authentication = ''
            local all all ident map=explorer-users
          '';
        };

        services = {
          # Profile cardano-postgres is tuned for 70% of RAM, leaving ~20% for node
          # and 10% for other services (dbsync smash) and overhead.
          cardano-node.totalMaxHeapSizeMiB = cfg.nodeRamAvailableMiB;
          cardano-postgres.ramAvailableMiB = cfg.postgresRamAvailableMiB;

          cardano-db-sync = {
            enable = true;
            package = cardano-db-sync;
            dbSyncPkgs = cardano-db-sync-pkgs;

            cluster = environmentName;
            environment = environmentConfig;
            socketPath = nodeCfg.socketPath 0;
            explorerConfig = environmentConfig.dbSyncConfig // {PrometheusPort = cardanoDbSyncPrometheusExporterPort;};
            logConfig = {};
            postgres.database = "cexplorer";
          };
        };

        # Ensure access to the cardano-node socket
        users = {
          groups.cardano-db-sync = {};
          users.cardano-db-sync = {
            extraGroups = ["cardano-node"];
            group = "cardano-db-sync";
            isSystemUser = true;
          };
        };
      };
    });
}
