{
  inputs,
  moduleWithSystem,
  ...
}: {
  flake.nixosModules.basic = moduleWithSystem ({system}: {
    name,
    config,
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

    # On boot, SOPS runs in stage 2 without networking, this prevents KMS from
    # working, so we repeat the activation script until decryption succeeds.
    systemd.services.sops-boot-fix = {
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];

      script = ''
        ${config.system.activationScripts.setupSecrets.text}

        # For wireguard enabled machines
        { systemctl list-unit-files wireguard-wg0.service &> /dev/null \
          && systemctl restart wireguard-wg0.service; } || true
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "2s";
      };
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
      file
      git
      glances
      helix
      htop
      iptables
      jq
      lsof
      nano
      ncdu
      parted
      pciutils
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
      chrony.enable = true;
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
        max-jobs = "auto";
        experimental-features = ["nix-command" "fetch-closure" "flakes" "cgroups"];
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
