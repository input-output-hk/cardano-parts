# nixosModule: profile-basic
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
{
  inputs,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.profile-basic = moduleWithSystem ({
    self',
    system,
  }: {
    config,
    name,
    pkgs,
    lib,
    ...
  }:
    with builtins;
    with lib; {
      key = ./profile-basic.nix;

      config = {
        deployment.targetHost = mkDefault name;

        networking = {
          hostName = name;
          firewall.enable = true;
        };

        time.timeZone = "UTC";
        i18n.supportedLocales = ["en_US.UTF-8/UTF-8" "en_US/ISO-8859-1"];

        boot = {
          tmp.cleanOnBoot = true;
          kernelParams = ["boot.trace"];
          loader.grub.configurationLimit = 10;
        };

        documentation = {
          nixos.enable = false;
          man.man-db.enable = false;
          info.enable = false;
          doc.enable = false;
        };

        environment = {
          shellAliases = {
            # Remote to remote rsync over ssm is likely to be bandwidth limited
            # due to proxying. Consider using wush instead. An alias is used in
            # preference over bash function for better discoverability.
            #
            # Example usage, where the hostname in the rsync args is the EC2 ID:
            #   rsync-ssm "$REGION" "$RSYNC_ARGS[@]"
            rsync-ssm = ''
              rsyncSsm(){
                if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
                  echo "If needed, short term credentials from the deployer can be generated with \"just aws-sso-export\" and sourced on this machine."
                fi
                REGION="$1"
                ARGS="''${@:2}"
                rsync -e "ssh -o $(ssm-proxy-rsync $REGION)" ''${ARGS[@]};
              }
              rsyncSsm "$@" \
            '';
          };

          # These can be discovered with `declare -F` for bash function name only and `declare -f` for code
          shellInit = ''
            # This can be used to simplify ssh sessions, ex: `ssh -o "$(ssm-proxy-cmd "$REGION")" "$INSTANCE_ID"`
            ssm-proxy-cmd() {
              echo "ProxyCommand=sh -c 'aws --region $1 ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p'"
            }

            # This is used to simplify rsync sessions with the rsync-ssm alias: `rsync-ssm "$REGION" "$RSYNC_ARGS[@]"`
            ssm-proxy-rsync () {
              echo "ProxyCommand='sh -c \"aws --region $1 ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p\"'"
            }
          '';

          systemPackages = with pkgs; [
            awscli2
            age
            bat
            bind
            cloud-utils
            di
            dnsutils
            fd
            fx
            file
            git
            glances
            helix
            htop
            icdiff
            ijq
            iptables
            self'.packages.isd
            jiq
            jq
            # Because there's a bug in lnav 0.12.4, when used in tmux.
            # NOTE: Next update of nixpkgs-unstable will get the version that fixes the tmux bug.
            inputs.nixpkgs-unstable.legacyPackages.${system}.lnav
            lsof
            nano
            # For nix >= 2.24 build compatibility
            inputs.nixpkgs-unstable.legacyPackages.${system}.neovim
            ncdu
            # Add a localFlake pin to avoid downstream repo nixpkgs pins <= 24.11 causing missing features error
            inputs.nixpkgs.legacyPackages.${system}.nushell
            nvme-cli
            parted
            pciutils
            procps
            ripgrep
            rsync
            ssm-session-manager-plugin
            smem
            ssh-to-age
            sops
            sysstat
            tcpdump
            tree
            wget
            wush
          ];
        };

        programs = {
          tmux = {
            enable = true;
            aggressiveResize = true;
            clock24 = true;
            escapeTime = 0;
            historyLimit = 10000;
            newSession = true;
          };
        };

        services = {
          chrony = {
            enable = true;
            extraConfig = "rtcsync";
            enableRTCTrimming = false;
          };

          cron.enable = true;
          fail2ban.enable = true;
          netdata.enable = true;
          openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              RequiredRSASize = 2048;
              PubkeyAcceptedAlgorithms = "-*nist*";
            };
          };
        };

        system.extraSystemBuilderCmds = ''
          ln -sv ${pkgs.path} $out/nixpkgs
        '';

        nix = {
          package = inputs.nix.packages.${system}.nix;
          registry.nixpkgs.flake = inputs.nixpkgs;

          # Setting this true will typically induce iowait at ~50% level for
          # several minutes each day on already IOPS constrained ec2 ebs gp3 and
          # similarly capable machines, which in turn may impact performance for
          # capability sensitive software.  While cardano-node itself doesn't
          # appear to be impacted by this in terms of observable missedSlots on
          # forgers or delayed headers reported by blockperf, this will be
          # disabled as a precaution.
          optimise.automatic = false;

          gc = {
            automatic = true;

            # Minimize security vulnerability positive scan results by flushing old closures
            options = "--delete-older-than 30d";
          };

          settings = {
            auto-optimise-store = true;
            builders-use-substitutes = true;
            experimental-features = ["nix-command" "fetch-closure" "flakes" "cgroups"];
            keep-derivations = true;
            keep-outputs = true;
            max-jobs = "auto";
            show-trace = true;
            substituters = ["https://cache.iog.io"];
            system-features = ["recursive-nix" "nixos-test"];
            tarball-ttl = 60 * 60 * 72;
            trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
          };
        };

        security.tpm2 = {
          enable = true;
          pkcs11.enable = true;
        };

        hardware = {
          cpu.amd.updateMicrocode = true;
          cpu.intel.updateMicrocode = true;
          enableRedistributableFirmware = true;
        };

        system.stateVersion = "23.05";

        warnings = let
          nixosRelease = config.system.nixos.release;
          nixpkgsRelease = sanitize inputs.nixpkgs.lib.version;
          match' = versionStr: match ''^([[:d:]]+\.[[:d:]]+).*$'' versionStr;
          sanitize = versionStr:
            if isList (match' versionStr)
            then head (match' versionStr)
            else versionStr;
        in
          optional (nixosRelease != nixpkgsRelease)
          "Cardano-parts nixosModules have been tested with release ${nixpkgsRelease}, whereas this nixosConfiguration is using release ${nixosRelease}";
      };
    });
}
