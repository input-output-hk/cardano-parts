{
  inputs,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.common = moduleWithSystem ({
    name,
    pkgs,
    ...
  }: {
    imports = [];

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
    programs.sysdig.enable = true;
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
      bat
      bind
      di
      dnsutils
      fd
      file
      htop
      helix
      jq
      lsof
      ncdu
      ripgrep
      tree
      nano
      tcpdump
      glances
      gitMinimal
      pciutils
    ];

    programs.tmux = {
      enable = true;
      aggressiveResize = true;
      clock24 = true;
      escapeTime = 0;
      historyLimit = 10000;
      newSession = true;
    };

    services = {
      chrony.enable = true;
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

    nix = {
      registry.nixpkgs.flake = inputs.nixpkgs;
      optimise.automatic = true;
      gc.automatic = true;

      settings = {
        max-jobs = "auto";
        experimental-features = ["nix-command" "flakes" "cgroups"];
        auto-optimise-store = true;
        system-features = ["recursive-nix" "nixos-test"];
        builders-use-substitutes = true;
        show-trace = true;
        keep-outputs = true;
        keep-derivations = true;
        tarball-ttl = 60 * 60 * 72;
      };
    };

    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;
    };

    hardware = {
      cpu.amd.updateMicrocode = true;
      enableRedistributableFirmware = true;
    };
  });
}
