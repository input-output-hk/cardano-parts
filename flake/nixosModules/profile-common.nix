# nixosModule: profile-common
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#   config.programs.auth-keys-hub.<...>
#   config.sops.<...>
#
# Tips:
# * Repository authentication permissions and repository token secret
# will typically be declared in the consuming repo.
#
# * Example:
#   ../../templates/cardano-parts-project/flake/nixosModules/common.nix
{
  self,
  inputs,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.profile-common = moduleWithSystem ({system}: {
    config,
    pkgs,
    lib,
    ...
  }: let
    inherit (builtins) toJSON;
    # nixpkgsUpgrade: current migration workaround
    # Suppress system and user D-Bus change-triggered reloads and restarts
    # during the dbus-daemon to dbus-broker migration: the running daemon
    # cannot complete the new broker unit's notify-reload handshake.
    # Disable after the entire cluster has upgraded AND rebooted into broker.
    # Normal startup is unaffected, including across multiple reboots, but
    # subsequent D-Bus changes may wait until reboot while this is enabled.
    # Permanent SSM/DNS activation protection below is independent of this flag.
    # Read the flag from the consuming cluster, not cardano-parts' own config.
    nixpkgsUpgrade = config.cardano-parts.cluster.group.groupFlake.config.flake.cardano-parts.cluster.infra.generic.nixpkgsUpgrade or false;
    deferDbusChanges = {
      reloadIfChanged = lib.mkForce false;
      restartIfChanged = false;
    };
  in
    with pkgs;
    with lib; {
      imports = [
        inputs.sops-nix.nixosModules.default
        inputs.auth-keys-hub.nixosModules.auth-keys-hub
      ];

      key = ./profile-common.nix;

      config = {
        boot = {
          # Mitigate Copy.Fail (CVE-2026-31431) and Dirty Frag and Fragnesia (CVE-2026-43284, CVE-2026-43500, CVE-2026-46300).
          # Safe to remove once kernel has the right patches, likely when cardano-parts updates to nixpkgs 26.05.
          blacklistedKernelModules = ["algif_aead" "esp4" "esp6" "rxrpc"];
          extraModprobeConfig = ''
            install algif_aead ${coreutils}/bin/false
            install esp4 ${coreutils}/bin/false
            install esp6 ${coreutils}/bin/false
            install rxrpc ${coreutils}/bin/false
          '';
        };
        # Unload vulnerable modules immediately
        system.activationScripts.cve-rmmod = ''
          ${kmod}/bin/rmmod algif_aead 2>/dev/null || true
          ${kmod}/bin/rmmod esp4 2>/dev/null || true
          ${kmod}/bin/rmmod esp6 2>/dev/null || true
          ${kmod}/bin/rmmod rxrpc 2>/dev/null || true
        '';

        environment = {
          # Enable terminfo for common terminal types like `xterm-256color` and `tmux-256color`.
          enableAllTerminfo = mkDefault true;

          # Use C locale for time to ensure consistent date retrieval and log timestamp formatting.
          variables.LC_TIME = mkDefault "C";
        };

        programs = {
          auth-keys-hub = {
            enable = mkDefault true;
            package = inputs.auth-keys-hub.packages.${system}.auth-keys-hub;

            # Avoid loss of access edge cases associated with use of ephemeral authorized_keys storage
            # Edge case example:
            #   * Both auth-keys-hub state and github token default to the /run ephemeral state dir or subdirs for default secrets storage
            #   * Only a github team is declared for auth-keys-hub access
            #   * The machine is rebooted
            #   * Auth keys hub state is now gone and a github token is required to pull new authorized key state, but that's gone too
            #   * Machine lockout occurs
            dataDir = "/var/lib/auth-keys-hub";
          };
        };

        services = {
          # Enable the at scheduler
          atd.enable = true;

          # Collect some system metrics locally at higher resolution than the
          # default exported metrics which is typically a rate of 1 sample/min
          sysstat = {
            enable = true;

            # Also include disk statistics by partition and filesystem not collected by default
            collect-args = "1 1 -S XDISK";

            # Collect every 10 seconds, with accuracy enforced in the systemd timer
            collect-frequency = "*:*:00/10";
          };
        };

        system.systemBuilderCommands = ''
          printf '%s' ${
            escapeShellArg (toJSON ((removeAttrs self.sourceInfo ["outPath"]) // {outPathStr = self.sourceInfo.outPath;}))
          } > $out/source-info-cardano-parts.json
        '';

        systemd = {
          # See nixpkgsUpgrade above for migration details and removal criteria.
          # Both aliases and both scopes need the override.
          user.services = mkIf (nixpkgsUpgrade && config.services.dbus.enable) {
            dbus = deferDbusChanges;
            dbus-broker = mkIf (config.services.dbus.implementation == "broker") deferDbusChanges;
          };
          services = {
            # Permanent deployment protection: retain access and DNS during
            # activation (including AWS KMS decryption), then restart changed
            # services later in the switch. Independent of nixpkgsUpgrade.
            amazon-ssm-agent = mkIf config.services.amazon-ssm-agent.enable {
              stopIfChanged = mkDefault false;
            };
            dnsmasq = mkIf config.services.dnsmasq.enable {
              stopIfChanged = mkDefault false;
            };
            dbus = mkIf (nixpkgsUpgrade && config.services.dbus.enable) deferDbusChanges;
            dbus-broker = mkIf (nixpkgsUpgrade && config.services.dbus.enable && config.services.dbus.implementation == "broker") deferDbusChanges;

            # Remove the bootstrap key after 1 week in favor of auth-keys-hub use
            remove-ssh-bootstrap-key = {
              wantedBy = ["multi-user.target"];

              serviceConfig = {
                Type = "oneshot";

                ExecStart = getExe (writeShellApplication {
                  name = "remove-ssh-bootstrap-key";
                  runtimeInputs = [fd gnugrep gnused];
                  text = ''
                    mkdir -p /root/.ssh && chmod 0600 /root/.ssh
                    if ! [ -f /root/.ssh/.bootstrap-key-removed ]; then
                      # Verify auth keys is properly hooked into sshd
                      if ! grep -q 'AuthorizedKeysCommand /etc/ssh/auth-keys-hub --user %u' /etc/ssh/sshd_config; then
                        echo "SSH daemon authorized keys command does not appear to have auth-keys-hub installed"
                        exit
                      fi

                      if ! grep -q 'AuthorizedKeysCommandUser ${config.programs.auth-keys-hub.user}' /etc/ssh/sshd_config; then
                        echo "SSH daemon authorized keys command user does not appear to be using the ${config.programs.auth-keys-hub.user} user"
                        exit
                      fi

                      # Ensure at least 1 ssh key is declared outside of auth-keys-hub
                      if ! grep -q -E '^ssh-' /etc/ssh/authorized_keys.d/root &> /dev/null; then
                        echo "You must declare at least 1 authorized key via users.users.root.openssh.authorizedKeys attribute before the bootstrap key will be removed"
                        exit
                      fi

                      # Allow 1 week of bootstrap key use before removing it
                      if fd --quiet --changed-within 7d authorized_keys /root/.ssh; then
                        echo "The root authorized_keys file has been changed within the past week; waiting a little longer before removing the bootstrap key"
                        exit
                      fi

                      # Remove the bootstrap key and set a marker
                      echo "Removing the bootstrap key from /root/.ssh/authorized_keys"
                      if [ -s /root/.ssh/authorized_keys ]; then
                        sed -i '/bootstrap/d' /root/.ssh/authorized_keys
                      fi
                      touch /root/.ssh/.bootstrap-key-removed
                    fi
                  '';
                });
              };
            };

            # On boot SOPS runs in stage 2 without networking.
            # For repositories using KMS sops secrets, this prevents KMS from working,
            # so we repeat the activation script until decryption succeeds.
            #
            # Sops-nix module does provide a systemd restart and reload hook for
            # associated secrets changes with the option:
            #
            #   sops.secrets.<name>.<restartUnits|reloadUnits>
            #
            # Although the sops-nix restart or reload options are preferred,
            # sops-secrets service can also act as a generic systemd hook
            # for services needing to be restarted after new sops secrets are pushed.
            #
            # Example usage:
            #   systemd.services.<name> = {
            #     after = ["sops-secrets.service"];
            #     wants = ["sops-secrets.service"];
            #     partOf = ["sops-secrets.service"];
            #   };
            #
            sops-secrets = {
              wantedBy = ["multi-user.target"];

              script = config.system.activationScripts.setupSecrets.text or "true";

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                Restart = "on-failure";
                RestartSec = "2s";
              };
            };
          };

          timers = {
            remove-ssh-bootstrap-key = {
              wantedBy = ["timers.target"];
              timerConfig = {
                OnCalendar = "daily";
                Unit = "remove-ssh-bootstrap-key.service";
              };
            };

            # Enforce accurate 10 second sysstat sampling intervals
            sysstat-collect.timerConfig.AccuracySec = "1us";
          };
        };

        sops.defaultSopsFormat = "binary";
      };
    });
}
