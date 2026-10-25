{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ]
  # Disk-encryption settings the installer wrote, if any (see scripts/bootstrap.sh).
  ++ lib.optional (builtins.pathExists ./installer-extras.nix) ./installer-extras.nix;

  # Pushing to main on GitHub updates this laptop within about 5 minutes.
  services.nixos-git-deploy = {
    enable = true;
    repo = "pawel-li/nixos-config";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "laptop";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";
  services.xserver.xkb.layout = "pl";
  console.keyMap = "pl2";

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth.enable = true;
  hardware.enableRedistributableFirmware = true;
  services.fwupd.enable = true;
  services.printing.enable = true;

  # Stays on around the clock so the services below are always reachable:
  # closing the lid does nothing, and nothing can suspend or hibernate it.
  # The screen still turns off when idle.
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
  # GNOME's idle timers, at the login screen and in your session, so it never
  # tries (or offers) to suspend. The power button asks what to do.
  services.displayManager.gdm.autoSuspend = false;
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing";
        power-button-action = "interactive";
      };
    }
  ];
  # In a power cut it keeps going on battery, then shuts down cleanly when the
  # battery is nearly empty (the default, hybrid sleep, is switched off above).
  services.upower.criticalPowerAction = "PowerOff";

  nixpkgs.config.allowUnfree = true;

  users.users.pawel = {
    isNormalUser = true;
    description = "Pawel";
    extraGroups = [ "wheel" "networkmanager" ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  # Services here are for the whole home network: each one listens on every
  # address and opens its port in the firewall. Other devices reach them at
  # laptop.local, which avahi announces on the network. nssmdns4 lets the
  # laptop itself use .local names too, so the same links work everywhere.
  services.avahi = {
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Glance: the start page, http://laptop.local:8080. Links to every service
  # below and shows whether each one is up.
  services.glance = {
    enable = true;
    openFirewall = true;
    settings = {
      server.host = "[::]"; # every address, IPv4 and IPv6
      pages = [
        {
          name = "Home";
          columns = [
            {
              size = "small";
              widgets = [
                { type = "calendar"; }
                { type = "server-stats"; }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "monitor";
                  title = "Services";
                  cache = "1m";
                  # url is the link; check-url is what Glance itself polls.
                  sites = [
                    {
                      title = "Jellyfin";
                      url = "http://laptop.local:8096";
                      check-url = "http://127.0.0.1:8096/health";
                      icon = "di:jellyfin";
                    }
                    {
                      title = "Navidrome";
                      url = "http://laptop.local:4533";
                      check-url = "http://127.0.0.1:4533/app/";
                      icon = "di:navidrome";
                    }
                    {
                      title = "Paperless";
                      url = "http://laptop.local:28981";
                      check-url = "http://127.0.0.1:28981/accounts/login/";
                      icon = "di:paperless-ngx";
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };

  # Jellyfin: films, series and music, http://laptop.local:8096. The first visit
  # walks you through creating the admin account and adding ~/Videos and
  # ~/Music as libraries. Like Navidrome below, it runs as pawel and sees only
  # those two folders, read-only.
  services.jellyfin = {
    enable = true;
    user = "pawel";
    group = "users";
    openFirewall = true;
  };
  systemd.services.jellyfin.serviceConfig = {
    ProtectHome = "tmpfs";
    BindReadOnlyPaths = [
      "/home/pawel/Videos"
      "/home/pawel/Music"
    ];
  };
  # Creates ~/Videos if it's missing, so Jellyfin can start. (Navidrome's
  # module does the same for ~/Music.)
  systemd.tmpfiles.settings.jellyfinMedia."/home/pawel/Videos".d = {
    mode = ":755";
    user = ":pawel";
    group = ":users";
  };

  # Paperless-ngx: scanned documents and PDFs, searchable, at
  # http://laptop.local:28981. Create your login once with
  # `sudo paperless-manage createsuperuser`, then drop files onto the page.
  services.paperless = {
    enable = true;
    address = "::"; # every address, IPv4 and IPv6
    # Read Polish and English. This goes in a file and not in `settings`:
    # setting the language there makes NixOS rebuild Paperless with only those
    # languages, which the laptop would compile itself after every nixpkgs
    # update. The standard build already has them all.
    environmentFile = pkgs.writeText "paperless-env" ''
      PAPERLESS_OCR_LANGUAGE=pol+eng
    '';
  };
  networking.firewall.allowedTCPPorts = [ config.services.paperless.port ];

  # Navidrome music server. Put music in ~/Music, then open
  # http://laptop.local:4533; the first visit asks you to create the admin
  # account. It runs as pawel so it can read whatever you copy there, and it
  # sees only that folder, read-only.
  services.navidrome = {
    enable = true;
    user = "pawel";
    group = "users";
    openFirewall = true;
    settings = {
      MusicFolder = "/home/pawel/Music";
      Address = "[::]"; # every address, IPv4 and IPv6
    };
  };
  # The module hides all of /home from Navidrome. "tmpfs" hides it too, but lets
  # the ~/Music folder above show through.
  systemd.services.navidrome.serviceConfig.ProtectHome = lib.mkForce "tmpfs";

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    curl
    gh
    git
    vim
  ];

  # The NixOS release this laptop was first installed with. Leave it as is,
  # even after moving nixpkgs to a newer release.
  system.stateVersion = "26.05";
}
