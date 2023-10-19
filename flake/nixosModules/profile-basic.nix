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
  flake.nixosModules.profile-basic = moduleWithSystem ({system}: {
    name,
    pkgs,
    ...
  }: {
    deployment.targetHost = name;

    networking = {
      hostName = name;
      firewall = {
        enable = true;
        allowedTCPPorts = [22];
        allowedUDPPorts = [];
      };
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

    environment.systemPackages = with pkgs; [
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
      ijq
      icdiff
      iptables
      jiq
      jq
      lsof
      nano
      neovim
      ncdu
      parted
      pciutils
      procps
      ripgrep
      rsync
      ssh-to-age
      sops
      sysstat
      tcpdump
      tree
    ];

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
      };

      cron.enable = true;
      fail2ban.enable = true;
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
      optimise.automatic = true;
      gc.automatic = true;

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
  });
}
