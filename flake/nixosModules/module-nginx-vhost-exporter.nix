# nixosModule: module-nginx-vhost-exporter
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.nginx-vhost-exporter.address
#   config.services.nginx-vhost-exporter.enable
#   config.services.nginx-vhost-exporter.port
#
# Tips:
#   * Import this module to export nginx vhost traffic metrics
{
  flake.nixosModules.module-nginx-vhost-exporter = {
    pkgs,
    config,
    lib,
    ...
  }:
    with lib; let
      inherit (types) bool port str;

      cfg = config.services.nginx-vhost-exporter;
    in {
      options = {
        services.nginx-vhost-exporter = {
          address = mkOption {
            type = str;
            default = "127.0.0.1";
            description = "The listen address for the nginx vhost traffic status module to bind.";
          };

          enable = mkOption {
            type = bool;
            default = false;
            description = "Whether to enable nginx vts module vhost traffic export metrics.";
          };

          port = mkOption {
            type = port;
            default = 9113;
            description = "The port for the nginx vhost traffic status module to bind.";
          };
        };
      };

      config = mkIf cfg.enable {
        services.nginx = {
          additionalModules = [pkgs.nginxModules.vts];
          appendHttpConfig = ''
            # This config enables prom metrics exported to: /status/format/prometheus
            vhost_traffic_status_zone;
            server {
              listen ${cfg.address}:${toString cfg.port};
              location /status {
                vhost_traffic_status_display;
                vhost_traffic_status_display_format html;
              }
            }
          '';
        };
      };
    };
}
