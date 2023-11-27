# nixosModule: profile-cardano-webserver
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-webserver.acmeEmail
#   config.services.cardano-webserver.acmeProd
#   config.services.cardano-webserver.enableAcme
#   config.services.cardano-webserver.openFirewallNginx
#   config.services.cardano-webserver.serverAliases
#   config.services.cardano-webserver.serverName
#   config.services.cardano-webserver.varnishExporterPort
#   config.services.cardano-webserver.varnishRamAvailableMiB
#   config.services.cardano-webserver.varnishRestartWithNginx
#   config.services.cardano-webserver.varnishTtl
#   config.services.cardano-webserver.vhostsDir
#   config.services.nginx-vhost-exporter.address
#   config.services.nginx-vhost-exporter.enable
#   config.services.nginx-vhost-exporter.port
#
# Tips:
#   * This is a cardano-webserver profile which provides a varnish caching generic webserver
#   * Any subdirectories found under cfg.vhostsDir will be automatically set up as virtualhosts and their contents served
flake: {
  flake.nixosModules.profile-cardano-webserver = {
    config,
    pkgs,
    lib,
    name,
    nodeResources,
    ...
  }:
    with builtins;
    with lib; let
      inherit (types) bool float ints listOf oneOf port str;
      inherit (groupCfg) groupFlake;
      inherit (groupCfg.meta) domain;
      inherit (nodeResources) memMiB;

      groupCfg = config.cardano-parts.cluster.group;

      roundFloat = f:
        if f >= (floor f + 0.5)
        then ceil f
        else floor f;

      cfg = config.services.cardano-webserver;
    in {
      imports = [flake.config.flake.nixosModules.module-nginx-vhost-exporter];

      options = {
        services.cardano-webserver = {
          acmeEmail = mkOption {
            type = str;
            default = null;
            description = "The default contact email to be used for ACME certificate aquisition.";
          };

          acmeProd = mkOption {
            type = bool;
            default = true;
            description = "Whether to use the ACME TLS production server for certificate requests.";
          };

          enableAcme = mkOption {
            type = bool;
            default = true;
            description = "Whether to obtain an ACME TLS cert for nginx.";
          };

          openFirewallNginx = mkOption {
            type = bool;
            default = true;
            description = "Whether to open the firewall TCP ports used by nginx: 80, 443";
          };

          serverAliases = mkOption {
            type = listOf str;
            default = [];
            description = "Extra FQDN aliases to be added to the ACME TLS cert for nginx.";
          };

          serverName = mkOption {
            type = str;
            default = "${name}.${domain}";
            description = "The default server name for nginx.";
          };

          varnishExporterPort = mkOption {
            type = port;
            default = 9131;
            description = "The port for the varnish metrics exporter to listen on.";
          };

          varnishRamAvailableMiB = mkOption {
            type = oneOf [ints.positive float];
            default = memMiB * 0.10;
            description = "The max amount of RAM to allocate to for varnish object memory backend store.";
          };

          varnishRestartWithNginx = mkOption {
            type = bool;
            default = true;
            description = "Whether to restart varnish any time that nginx is restarted.";
          };

          varnishIgnoreCookies = mkOption {
            type = bool;
            default = true;
            description = ''
              By default, varnish will not return cached results for requests which contain cookies.

              If vhost content does not use cookies, cache hit rate may be low due to unrelated or client injected cookies.
              Setting this to true will cause varnish to return cached results even if the request contains cookies.
            '';
          };

          varnishTtl = mkOption {
            type = ints.positive;
            default = 30;
            description = "The number of days for varnish server cache object TTL.";
          };

          vhostsDir = mkOption {
            type = str;
            default = "${groupFlake.self.outPath}/static";
            description = ''
              The repo directory under which virtualHost subdirectories and/or symlinks exist, with their contents.

              Example:
                ${cfg.vhostsDir}/site1.fqdn1.com/index.html
                ${cfg.vhostsDir}/site2.fqdn2.com/index.html
                ${cfg.vhostsDir}/site3.fqdn2.com -> ${cfg.vhostsDir}/site1.fqdn1.com/index.html

              In the example above, both site[12].fqdn[12].com will be automatically set up as nginx virtual hosts,
              TLS terminated at nginx, cached through varnish and the contents of those virtual host directories served
              through nginx to varnish.

              Site3 is a symlink to site1 dir and so the FQDN for site3.fqdn2.com will be set up as a virtualhost with
              the contents of site1.fqdn1.com.
            '';
          };
        };
      };

      config = {
        services.varnish = {
          enable = true;
          extraCommandLine = "-t ${toString (cfg.varnishTtl * 24 * 3600)} -s malloc,${toString (roundFloat cfg.varnishRamAvailableMiB)}M";
          config = ''
            vcl 4.1;

            import std;

            backend default {
              .host = "127.0.0.1";
              .port = "8080";
            }

            acl purge {
              "localhost";
              "127.0.0.1";
            }

            sub vcl_recv {
              unset req.http.x-cache;

              ${optionalString cfg.varnishIgnoreCookies "unset req.http.cookie;"}

              # Allow PURGE from localhost
              if (req.method == "PURGE") {
                if (!std.ip(req.http.X-Real-Ip, "0.0.0.0") ~ purge) {
                  return(synth(405,"Not Allowed"));
                }

                # If needed, host can be passed in the curl purge request with -H "Host: $HOST"
                # along with an allow listed X-Real-Ip header.
                return(purge);
              }
            }

            sub vcl_hit {
              set req.http.x-cache = "hit";
            }

            sub vcl_miss {
              set req.http.x-cache = "miss";
            }

            sub vcl_pass {
              set req.http.x-cache = "pass";
            }

            sub vcl_pipe {
              set req.http.x-cache = "pipe";
            }

            sub vcl_synth {
              set req.http.x-cache = "synth synth";
              set resp.http.x-cache = req.http.x-cache;
            }

            sub vcl_deliver {
              if (obj.uncacheable) {
                set req.http.x-cache = req.http.x-cache + " uncacheable";
              }
              else {
                set req.http.x-cache = req.http.x-cache + " cached";
              }
              set resp.http.x-cache = req.http.x-cache;
            }

            sub vcl_backend_response {
              if (bereq.uncacheable) {
                return (deliver);
              }
              if (beresp.status == 404) {
                set beresp.ttl = 1h;
              }
              call vcl_beresp_stale;
              call vcl_beresp_cookie;
              call vcl_beresp_control;
              call vcl_beresp_vary;
              return (deliver);
            }
          '';
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewallNginx [80 443];

        security.acme = mkIf cfg.enableAcme {
          acceptTerms = true;
          defaults = {
            email = cfg.acmeEmail;
            server =
              if cfg.acmeProd
              then "https://acme-v02.api.letsencrypt.org/directory"
              else "https://acme-staging-v02.api.letsencrypt.org/directory";
          };
        };

        services.nginx-vhost-exporter.enable = true;

        services.nginx = {
          enable = true;
          eventsConfig = "worker_connections 4096;";
          appendConfig = "worker_rlimit_nofile 16384;";
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          commonHttpConfig = ''
            log_format x-fwd '$remote_addr - $remote_user [$time_local] '
                             '"$scheme://$host" "$request" "$http_accept_language" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent" "$http_x_forwarded_for"';

            access_log syslog:server=unix:/dev/log x-fwd;
            limit_req_zone $binary_remote_addr zone=perIP:100m rate=1r/s;
            limit_req_status 429;

            map $http_accept_language $lang {
                    default en;
                    ~de de;
                    ~ja ja;
            }
          '';

          virtualHosts = let
            backendListen = [
              {
                addr = "127.0.0.1";
                port = 8080;
              }
            ];

            extraVhostConfig = {
              locations."/favicon.ico".extraConfig = ''
                return 204;
                access_log off;
                log_not_found off;
              '';
            };

            nameCheck = map (name:
              if elem name ["healthCheck" "tlsTerminator"]
              then abort ''ABORT: virtualhost name: "${name}" is reserved.''
              else name);

            vhostsDirList = attrNames (filterAttrs (_: v: v == "directory" || v == "symlink") (readDir cfg.vhostsDir));

            vhosts = foldl' (acc: vhostName:
              recursiveUpdate acc {
                ${vhostName} =
                  recursiveUpdate {
                    listen = backendListen;
                    locations."/".root = pkgs.runCommand vhostName {} "mkdir $out; cp -LR ${cfg.vhostsDir}/${vhostName}/* $out/";
                  }
                  extraVhostConfig;
              }) {}
            (nameCheck vhostsDirList);
          in
            {
              tlsTerminator =
                recursiveUpdate {
                  inherit (cfg) serverName;
                  serverAliases = cfg.serverAliases ++ (unique (sort (a: b: a < b) vhostsDirList));

                  default = true;
                  enableACME = cfg.enableAcme;
                  forceSSL = cfg.enableAcme;
                  locations."/".proxyPass = "http://127.0.0.1:6081";
                }
                extraVhostConfig;

              healthCheck =
                recursiveUpdate {
                  listen = backendListen;
                  default = true;
                  locations."/".root = pkgs.runCommand "health-check" {} ''mkdir $out; echo -n "Ready" > $out/index.html'';
                }
                extraVhostConfig;
            }
            // vhosts;
        };

        systemd.services.nginx.serviceConfig = {
          LimitNOFILE = 65535;
          LogNamespace = "nginx";
        };

        systemd.services.varnish.partOf = mkIf cfg.varnishRestartWithNginx ["nginx.service"];

        services.prometheus.exporters = {
          varnish = {
            enable = true;
            listenAddress = "127.0.0.1";
            port = cfg.varnishExporterPort;
            group = "varnish";
          };
        };
      };
    };
}
