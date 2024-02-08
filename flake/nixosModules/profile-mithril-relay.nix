# nixosModule: profile-mithril-relay
#
# TODO: Move this to a docs generator
#   config.services.mithril-relay.interface
#   config.services.mithril-relay.proxyPort
#   config.services.mithril-relay.signerIp
#
# Attributes available on nixos module import:
#
# Tips:
#   * This module relays requests from a mithril-signer to the mithril network aggregator using a forward proxy
flake: {
  flake.nixosModules.profile-mithril-relay = {
    config,
    lib,
    name,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types;
    inherit (types) port str;

    mkIpAction = action: apply: ip_addrs: methods: {
      inherit action apply ip_addrs methods;
    };

    cfg = config.services.mithril-relay;
  in {
    options.services.mithril-relay = {
      interface = mkOption {
        type = str;
        default = "ens5";
        description = "The default network interface to open the proxyPort on.";
      };

      proxyPort = mkOption {
        type = port;
        default = 3132;
        description = "The relay port the mithril signer must use in a production setup.";
      };

      signerIp = mkOption {
        type = str;
        default = null;
        description = "The mithril signer's ip for which the firewall will be opened at the proxyPort.";
      };
    };

    config = {
      networking.firewall = {
        extraCommands = "iptables -t filter -I nixos-fw -i ${cfg.interface} -p tcp -m tcp -s ${cfg.signerIp} --dport ${toString cfg.proxyPort} -j nixos-fw-accept";
        extraStopCommands = "iptables -t filter -D nixos-fw -i ${cfg.interface} -p tcp -m tcp -s ${cfg.signerIp} --dport ${toString cfg.proxyPort} -j nixos-fw-accept || true";
      };

      systemd.services.trafficserver = {
        # We would like to reload if any of the possible config modules are changed
        reloadIfChanged = true;
        serviceConfig.ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };

      services.trafficserver = {
        enable = true;
        records = {
          proxy = {
            config = {
              # Anonymize the forward proxy
              http = {
                anonymize_remove_from = 1;
                anonymize_remove_referer = 1;
                anonymize_remove_user_agent = 1;
                anonymize_remove_cookie = 1;
                anonymize_remove_client_ip = 1;

                cache.http = 0;
                insert_client_ip = 0;
                insert_squid_x_forwarded_for = 0;
                insert_request_via_str = 0;
                insert_response_via_str = 0;
                response_server_enabled = 0;
                server_ports = toString cfg.proxyPort;
              };

              # Set logging and disable reverse proxy
              log.logging_enabled = 3;
              reverse_proxy.enabled = 0;

              # Control access to the proxy via firewall and ip_allow rather than remap
              url_remap.remap_required = 0;
            };
          };
        };

        ipAllow.ip_allow = [
          (mkIpAction "allow" "in" cfg.signerIp "ALL")
          (mkIpAction "allow" "in" "127.0.0.1" "ALL")
          (mkIpAction "allow" "in" "::1" "ALL")
          (mkIpAction "deny" "in" "0/0" "ALL")
          (mkIpAction "deny" "in" "::/0" "ALL")
        ];

        logging.logging = {
          formats = [
            {
              format = "id=firewall time=\"%<cqtd> %<cqtt>\" fw=%<phn> pri=6 proto=%<cqus> duration=%<ttmsf> sent=%<psql> rcvd=%<cqhl> src=%<chi> dst=%<shi> dstname=%<shn> user=%<caun> op=%<cqhm> arg=\"%<cqup>\" result=%<pssc> ref=\"%<{Referer}cqh>\" agent=\"%<{user-agent}cqh>\" cache=%<crc>";
              name = "welf";
            }
            {
              format = "%<cqts> %<ttms> %<chi> %<crc>/%<pssc> %<psql> %<cqhm> %<cquc> %<caun> %<phr>/%<shn> %<psct>";
              name = "squid_seconds_only_timestamp";
            }
            {
              format = "%<cqtq> %<ttms> %<chi> %<crc>/%<pssc> %<psql> %<cqhm> %<cquc> %<caun> %<phr>/%<shn> %<psct>";
              name = "squid";
            }
            {
              format = "%<chi> - %<caun> [%<cqtn>] \"%<cqtx>\" %<pssc> %<pscl>";
              name = "common";
            }
            {
              format = "%<chi> - %<caun> [%<cqtn>] \"%<cqtx>\" %<pssc> %<pscl> %<sssc> %<sscl> %<cqcl> %<pqcl> %<cqhl> %<pshl> %<pqhl> %<sshl> %<tts>";
              name = "extended";
            }
            {
              format = "%<chi> - %<caun> [%<cqtn>] \"%<cqtx>\" %<pssc> %<pscl> %<sssc> %<sscl> %<cqcl> %<pqcl> %<cqhl> %<pshl> %<pqhl> %<sshl> %<tts> %<phr> %<cfsc> %<pfsc> %<crc>";
              name = "extended2";
            }
          ];

          logs = [
            {
              filename = "extended2";
              format = "extended2";
              mode = "ascii";
            }
          ];
        };
      };
    };
  };
}
