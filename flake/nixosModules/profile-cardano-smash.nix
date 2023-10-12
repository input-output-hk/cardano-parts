# nixosModule: profile-cardano-smash
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.services.cardano-smash.acmeEmail
#   config.services.cardano-smash.acmeProd
#   config.services.cardano-smash.enableAcme
#   config.services.cardano-smash.registeredRelaysExporterPort
#   config.services.cardano-smash.serverAliases
#   config.services.cardano-smash.serverName
#   config.services.cardano-smash.varnishExporterPort
#   config.services.cardano-smash.varnishFqdn
#   config.services.cardano-smash.varnishRamAvailableMiB
#   config.services.cardano-smash.varnishTtl
#   config.services.nginx-vhost-exporter.address
#   config.services.nginx-vhost-exporter.enable
#   config.services.nginx-vhost-exporter.port
#
# Tips:
#   * This is a cardano-smash add-on to the cardano-parts profile-cardano-db-sync nixos service module
#   * This module provides cardano-smash and registered relays exporter services through nginx and varnish
#   * The cardano-parts profile-cardano-db-sync nixos service module should still be imported separately
flake: {
  flake.nixosModules.profile-cardano-smash = {
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
      inherit (groupCfg.meta) domain environmentName;
      inherit (nodeResources) memMiB;

      inherit (perNodeCfg.meta) cardanoSmashDelistedPools;
      inherit (perNodeCfg.pkgs) cardano-smash cardano-db-sync-pkgs cardano-node-pkgs;

      groupCfg = config.cardano-parts.cluster.group;
      perNodeCfg = config.cardano-parts.perNode;

      roundFloat = f:
        if f >= (floor f + 0.5)
        then ceil f
        else floor f;

      cfg = config.services.cardano-smash;
      cfgDbsync = config.services.cardano-db-sync;
      cfgSmash = config.services.smash;
    in {
      imports = [flake.config.flake.nixosModules.module-nginx-vhost-exporter];

      options = {
        services.cardano-smash = {
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
            description = "Whether to obtain an ACME TLS cert for serving smash server via nginx.";
          };

          registeredRelaysExporterPort = mkOption {
            type = port;
            default = 8888;
            description = "The port for the registered relays metrics exporter to listen on.";
          };

          serverAliases = mkOption {
            type = listOf str;
            default = [];
            description = "Extra FQDN aliases to be added to the ACME TLS cert for serving smash server via nginx.";
          };

          serverName = mkOption {
            type = str;
            default = "${name}.${domain}";
            description = "The default server name for serving smash server via nginx.";
          };

          varnishExporterPort = mkOption {
            type = port;
            default = 9131;
            description = "The port for the varnish metrics exporter to listen on.";
          };

          varnishFqdn = mkOption {
            type = str;
            default = "${name}.${domain}";
            description = "The FQDN to be used for configuring smash server as a varnish backend.";
          };

          varnishRamAvailableMiB = mkOption {
            type = oneOf [ints.positive float];
            default = memMiB * 0.10;
            description = "The max amount of RAM to allocate to for smash server varnish object memory backend store.";
          };

          varnishTtl = mkOption {
            type = ints.positive;
            default = 30;
            description = "The number of days for smash server cache object TTL.";
          };
        };
      };

      config = {
        services.cardano-db-sync.additionalDbUsers = [
          "smash"
          "registered-relays-dump"
        ];

        services.varnish = {
          enable = true;
          extraCommandLine = "-t ${toString (cfg.varnishTtl * 24 * 3600)} -s malloc,${toString (roundFloat cfg.varnishRamAvailableMiB)}M";
          config = ''
            vcl 4.1;

            import std;

            backend default {
              .host = "127.0.0.1";
              .port = "${toString config.services.smash.port}";
            }

            acl purge {
              "localhost";
              "127.0.0.1";
            }

            sub vcl_recv {
              unset req.http.x-cache;

              # Allow PURGE from localhost
              if (req.method == "PURGE") {
                if (!std.ip(req.http.X-Real-Ip, "0.0.0.0") ~ purge) {
                  return(synth(405,"Not Allowed"));
                }

                # The host is included as part of the object hash
                # We need to match the public FQDN for the purge to be successful
                set req.http.host = "${cfg.varnishFqdn}";

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

        services.smash = {
          inherit environmentName;

          enable = true;
          package = cardano-smash;
          dbSyncPkgs = cardano-db-sync-pkgs;
          postgres = {inherit (cfgDbsync.postgres) database port user socketdir;};
          delistedPools = cardanoSmashDelistedPools;

          # TODO: Until no-basic-auth capkgs is available.
          # In the meantime, this is not publicly exposed.
          admins = toFile "admins" "admin,admin";
        };

        systemd.services.registered-relays-dump = let
          # Deprecated exclusions
          excludedPools = [];
          relays_exclude_file = toFile "relays-exclude.txt" (concatStringsSep "\n" []);

          extract_relays_sql = toFile "extract_relays.sql" ''
            SELECT array_to_json(array_agg(row_to_json(t))) FROM (
              SELECT COALESCE(ipv4, dns_name) AS addr, port FROM (
                SELECT min(update_id) AS update_id, ipv4, dns_name, port
                  FROM pool_relay
                  INNER JOIN pool_update ON pool_update.id = pool_relay.update_id
                  INNER JOIN pool_hash ON pool_update.hash_id = pool_hash.id
                  WHERE ${optionalString (excludedPools != []) "pool_hash.view NOT IN (${excludedPools}) AND "}
                  (
                    (ipv4 IS NULL AND dns_name NOT LIKE '% %')
                      OR
                    ipv4 !~ '(^0\.)|(^10\.)|(^100\.6[4-9]\.)|(^100\.[7-9]\d\.)|(^100\.1[0-1]\d\.)|(^100\.12[0-7]\.)|(^127\.)|(^169\.254\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.0\.0\.)|(^192\.0\.2\.)|(^192\.88\.99\.)|(^192\.168\.)|(^198\.1[8-9]\.)|(^198\.51\.100\.)|(^203.0\.113\.)|(^22[4-9]\.)|(^23[0-9]\.)|(^24[0-9]\.)|(^25[0-5]\.)'
                  )
                  GROUP BY ipv4, dns_name, port ORDER BY update_id
              ) t
            ) t;
          '';
        in {
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          path = with pkgs; [
            config.services.postgresql.package
            cardano-node-pkgs.cardano-cli
            coreutils
            curl
            dnsutils
            jq
            netcat
          ];
          environment = config.environment.variables;
          script = ''
            set -uo pipefail

            pingAddr() {
              index=$1
              addr=$2
              port=$3
              allAddresses=$(dig +nocookie +short -q "$addr" A || :)
              if [ -z "$allAddresses" ]; then
                allAddresses=$addr
              elif [ "$allAddresses" = ";; connection timed out; no servers could be reached" ]; then
                allAddresses=$addr
              fi

              while IFS= read -r ip; do
                set +e
                PING="$(timeout 7s cardano-cli ping -h "$ip" -p "$port" -m $CARDANO_NODE_NETWORK_ID -c 1 -q --json)"
                res=$?
                if [ $res -eq 0 ]; then
                  echo $PING | jq -c > /dev/null 2>&1
                  res=$?
                fi
                set -e
                if [ $res -eq 0 ]; then
                  >&2 echo "Successfully pinged $addr:$port (on ip: $ip)"
                  set +e
                  geoinfo=$(curl -s --retry 3 http://ip-api.com/json/$ip?fields=1105930)
                  res=$?
                  set -e
                  if [ $res -eq 0 ]; then
                    status=$(echo "$geoinfo" | jq -r '.status')
                    if [ "$status" == "fail" ]; then
                      message=$(echo "$geoinfo" | jq -r '.message')
                      >&2 echo "Failed to retrieved goip info for $ip: $message"
                      exit 1
                    fi
                    continent=$(echo "$geoinfo" | jq -r '.continent')
                    country_code=$(echo "$geoinfo" | jq -r '.countryCode')
                    if [ "$country_code" == "US" ]; then
                      state=$(echo $geoinfo | jq -r '.regionName')
                      if [ "$state" == "Washington, D.C." ]; then
                        state="District of Columbia"
                      fi
                    else
                      state=$country_code
                    fi
                    jq -c --arg addr "$addr" --arg port "$port" \
                      --arg continent "$continent" --arg state "$state" \
                      '{addr: $addr, port: $port|tonumber, continent: $continent, state: $state}' \
                      <<< '{}' \
                      > $index-relay.json
                    break
                  else
                    >&2 echo "Failed to retrieved goip info for $ip"
                    exit $res
                  fi
                else
                  >&2 echo "failed to cardano-cli ping $addr:$port (on ip: $ip)"
                fi
              done <<< "$allAddresses"
            }

            run() {
              epoch=$(cardano-cli query tip --testnet-magic $CARDANO_NODE_NETWORK_ID | jq .epoch)
              db_sync_epoch=$(psql -U ${cfgSmash.postgres.user} -t --command="select no from epoch_sync_time order by id desc limit 1;")

              if [ $(( $epoch - $db_sync_epoch )) -gt 1 ]; then
                >&2 echo "cardano-db-sync has not catch-up with current epoch yet. Skipping."
                exit 0
              fi

              excludeList="$(sort ${relays_exclude_file})"
              cd $STATE_DIRECTORY
              rm -f *-relay.json

              i=0
              for r in $(psql -U ${cfgSmash.postgres.user} -t < ${extract_relays_sql} | jq -c '.[]'); do
                addr=$(echo "$r" | jq -r '.addr')
                port=$(echo "$r" | jq -r '.port')
                resolved=$(dig +nocookie +short -q "$addr" A || :)

                if [ "$resolved" = ";; connection timed out; no servers could be reached" ]; then
                  sanitizedResolved=""
                else
                  sanitizedResolved="$resolved"
                fi

                allAddresses=$addr$'\n'$sanitizedResolved
                excludedAddresses=$(comm -12 <(echo -e "$allAddresses" | sort) <(echo "$excludeList"))
                nbExcludedAddresses=$(echo $excludedAddresses | wc -w)

                if [[ $nbExcludedAddresses == 0 ]]; then
                  ((i+=1))
                  pingAddr $i "$addr" "$port" &
                  sleep 1.5 # Due to rate limiting on ip-api.com
                else
                  >&2 echo "$addr excluded due to dns name or IPs being in exclude list:\n$excludedAddresses"
                fi
              done

              wait

              if test -n "$(find . -maxdepth 1 -name '*-relay.json' -print -quit)"; then
                echo "Found a total of $(find . -name '*-relay.json' -printf '.' | wc -m) relays to include in topology.json"
                find . -name '*-relay.json' -printf '%f\t%p\n' | sort -k1 -n | cut -d$'\t' -f2 | tr '\n' '\0' | xargs -r0 cat \
                  | jq -n '. + [inputs]' | jq '{ Producers : . }' > topology.json
                mkdir -p relays
                mv topology.json relays/topology.json
                rm *-relay.json
              else
                echo "No relays found!"
              fi
            }

            while true
            do
              run
              sleep 3600
            done
          '';
          # 3 failures at max within 24h:
          startLimitIntervalSec = 24 * 60 * 60;
          serviceConfig = {
            User = "registered-relays-dump";
            SupplementaryGroups = "cardano-node";
            StateDirectory = "registered-relays-dump";
            Restart = "always";
            RestartSec = "30s";
            StartLimitBurst = 3;
          };
        };

        users.users.registered-relays-dump = {
          isSystemUser = true;
          group = "registered-relays-dump";
        };

        users.groups.registered-relays-dump = {};

        systemd.services.registered-relays-exporter = {
          wantedBy = ["multi-user.target"];
          path = with pkgs; [coreutils netcat];
          script = ''
            IP="127.0.0.1"
            PORT="${toString cfg.registeredRelaysExporterPort}"
            FILE="/var/lib/registered-relays-dump/relays/topology.json"

            echo "Serving registered relays dump metrics for file $FILE at $IP:$PORT..."

            while true; do
              MTIME=$(date -r "$FILE" +%s || echo -n "0")
              BYTES=$(stat -c %s "$FILE" || echo -n "0")
              MTIME_DESC="# TYPE registered_relays_dump_mtime gauge"
              MTIME_SERIES="registered_relays_dump_mtime $MTIME"
              SIZE_DESC="# TYPE registered_relays_dump_bytes gauge"
              SIZE_SERIES="registered_relays_dump_bytes $BYTES"
              echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\n\r\n$MTIME_DESC\n$MTIME_SERIES\n$SIZE_DESC\n$SIZE_SERIES" | nc -W 1 -l "$IP" "$PORT"
              echo "$MTIME_SERIES"
              echo "$SIZE_SERIES"
            done
          '';

          serviceConfig = {
            Restart = "always";
            RestartSec = "30s";
          };
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.enableAcme [80 443];

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
                             '"$request" "$http_accept_language" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent" "$http_x_forwarded_for"';

            access_log syslog:server=unix:/dev/log x-fwd;
            limit_req_zone $binary_remote_addr zone=apiPerIP:100m rate=1r/s;
            limit_req_status 429;

            map $http_accept_language $lang {
                    default en;
                    ~de de;
                    ~ja ja;
            }

            # Deprecated
            map $arg_apiKey $api_client_name {
              default "";
            }

            # Deprecated
            map $http_origin $origin_allowed {
              default 0;
            }

            map $sent_http_x_cache $loggable_varnish {
              "hit cached" 0;
              default 1;
            }

            map $origin_allowed $origin {
              default "";
              1 $http_origin;
            }
          '';

          virtualHosts = {
            smash = {
              inherit (cfg) serverAliases serverName;

              default = true;
              enableACME = cfg.enableAcme;
              forceSSL = cfg.enableAcme;
              locations = let
                apiKeyConfig = ''
                  if ($arg_apiKey = "") {
                      return 401; # Unauthorized (please authenticate)
                  }
                  if ($api_client_name = "") {
                      return 403; # Forbidden (invalid API key)
                  }
                '';
                corsConfig = ''
                  add_header 'Vary' 'Origin' always;
                  add_header 'Access-Control-Allow-Origin' $origin always;
                  add_header 'Access-Control-Allow-Methods' 'GET, PATCH, OPTIONS' always;
                  add_header 'Access-Control-Allow-Headers' 'User-Agent,X-Requested-With,Content-Type' always;

                  if ($request_method = OPTIONS) {
                    add_header 'Access-Control-Max-Age' 1728000;
                    add_header 'Content-Type' 'text/plain; charset=utf-8';
                    add_header 'Content-Length' 0;
                    return 204;
                  }
                '';
                endpoints = [
                  "/swagger.json"
                  "/api/v1/metadata"
                  "/api/v1/errors"
                  "/api/v1/exists"
                  "/api/v1/enlist"
                  "/api/v1/delist"
                  "/api/v1/delisted"
                  "/api/v1/retired"
                  "/api/v1/status"
                  "/api/v1/tickers"
                ];
              in
                {
                  "/".root = pkgs.runCommand "nginx-root-dir" {} ''mkdir $out; echo -n "Ready" > $out/index.html'';
                  "/relays".root = "/var/lib/registered-relays-dump";
                }
                // recursiveUpdate (genAttrs endpoints (p: {
                  proxyPass = "http://127.0.0.1:6081${p}";
                  extraConfig = corsConfig;
                })) {
                  "/api/v1/delist".extraConfig = ''
                    ${corsConfig}
                    ${apiKeyConfig}
                  '';
                  "/api/v1/enlist".extraConfig = ''
                    ${corsConfig}
                    ${apiKeyConfig}
                  '';
                  "/api/v1/metadata".extraConfig = ''
                    ${corsConfig}
                  '';
                  "/api/v1/tickers".extraConfig = ''
                    ${corsConfig}
                    if ($request_method = GET) {
                      set $arg_apiKey "bypass";
                      set $api_client_name "bypass";
                    }
                    ${apiKeyConfig}
                  '';
                };
            };
          };
        };

        systemd.services.nginx.serviceConfig = {
          LimitNOFILE = 65535;
          LogNamespace = "nginx";
          SupplementaryGroups = "registered-relays-dump";
        };

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
