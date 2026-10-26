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

  # Glance: the start page, at http://laptop.local (nginx below passes port 80
  # on to it) and http://laptop.local:8080. Links to every service below and
  # shows whether each one is up.
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
                      title = "Immich";
                      url = "http://laptop.local:2283";
                      check-url = "http://127.0.0.1:2283/api/server/ping";
                      icon = "di:immich";
                    }
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
                    {
                      title = "JobOps";
                      url = "http://laptop.local:3005";
                      check-url = "http://127.0.0.1:3005/health";
                      icon = "mdi:briefcase-search";
                    }
                    {
                      title = "Coder";
                      url = "http://laptop.local:3000";
                      check-url = "http://127.0.0.1:3000/healthz";
                      icon = "di:coder";
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

  # Makes http://laptop.local/ show Glance. Also answers when the laptop is
  # opened by its IP address or any other name.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts.glance = {
      default = true;
      locations."/".proxyPass =
        "http://127.0.0.1:${toString config.services.glance.settings.server.port}";
    };
  };

  # Immich: photos and videos, http://laptop.local:2283. The first visit asks
  # you to create the admin account; then install the Immich app on your phone
  # to back its photos up here (they're kept in /var/lib/immich). To include
  # the photos already in ~/Pictures, add /home/pawel/Pictures under
  # Administration → External Libraries. Immich sees that folder read-only and
  # nothing else in your home folder. (Immich itself comes from NixOS unstable
  # for now; see flake.nix.)
  services.immich = {
    enable = true;
    host = "::"; # every address, IPv4 and IPv6
    openFirewall = true;
  };
  systemd.services.immich-server.serviceConfig = {
    ProtectHome = lib.mkForce "tmpfs";
    BindReadOnlyPaths = [ "/home/pawel/Pictures" ];
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
  # Creates ~/Videos and ~/Pictures if they're missing, so Jellyfin and Immich
  # can start. (Navidrome's module does the same for ~/Music.)
  systemd.tmpfiles.settings.mediaFolders =
    lib.genAttrs [ "/home/pawel/Videos" "/home/pawel/Pictures" ] (_: {
      d = {
        mode = ":755";
        user = ":pawel";
        group = ":users";
      };
    });

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

  # Ports for nginx, Paperless and Coder, whose modules can't open them themselves.
  networking.firewall.allowedTCPPorts = [
    80
    config.services.paperless.port
    3000 # Coder
  ];

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

  # JobOps: job search and applications, http://laptop.local:3005. It searches
  # job boards, scores each offer against your CV, writes a CV for the ones you
  # pick and tracks where you applied. The first visit asks you to create your
  # account. It isn't packaged for NixOS, so it runs in Docker from the
  # project's own image and keeps its data in /var/lib/job-ops. Settings that
  # can't be made on the page, such as Gmail access, go in /var/lib/job-ops/env
  # (see the README). Docker opens port 3005 itself, past the firewall.
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true; # weekly, clears out images replaced by updates
  };
  virtualisation.oci-containers = {
    backend = "docker";
    containers.job-ops = {
      image = "ghcr.io/dakheera47/job-ops:latest";
      ports = [ "3005:3001" ];
      volumes = [
        "/var/lib/job-ops/data:/app/data"
        "/var/lib/job-ops/codex-home:/app/codex-home"
        "/var/lib/job-ops/tectonic-cache:/root/.cache/Tectonic"
      ];
      environmentFiles = [ "/var/lib/job-ops/env" ];
    };
  };
  systemd.tmpfiles.settings.job-ops = {
    "/var/lib/job-ops".d.mode = "0700";
    "/var/lib/job-ops/env".f.mode = "0600";
  };
  # Moves JobOps to its latest release once a week. It restarts only when
  # there is a new one.
  systemd.services.job-ops-update = {
    description = "Update JobOps to its latest release";
    startAt = "weekly";
    path = [ config.virtualisation.docker.package ];
    serviceConfig.Type = "oneshot";
    script = ''
      image=${config.virtualisation.oci-containers.containers.job-ops.image}
      old=$(docker image inspect --format '{{.Id}}' "$image" || true)
      docker pull --quiet "$image"
      if [ "$(docker image inspect --format '{{.Id}}' "$image")" != "$old" ]; then
        systemctl restart docker-job-ops.service
      fi
    '';
  };

  # Coder: development machines ("workspaces") that you or an AI agent start
  # on demand, at http://laptop.local:3000. The first visit asks you to create
  # the admin account. Workspaces come from templates you pick on the page:
  # Docker runs them here on the laptop, the cloud ones (AWS, Google Cloud,
  # Azure, ...) on machines rented from that provider, whose keys go in
  # /var/lib/coder/env. With no access URL set, Coder opens a tunnel to a
  # public https://...try.coder.app address, so cloud machines and agents
  # outside the home network can reach it too (see the README).
  services.coder = {
    enable = true;
    listenAddress = "[::]:3000"; # every address, IPv4 and IPv6
    environment.file = "/var/lib/coder/env";
    # Without Terraform bundled, Coder downloads the version it's tested with
    # on first use. The bundled one is newer than Coder supports, and NixOS
    # doesn't prebuild it (its licence isn't free), so the laptop would
    # compile it itself after nixpkgs updates.
    package = pkgs.coder.override { terraform = pkgs.emptyDirectory; };
  };
  # Its module doesn't wait for the database it sets up.
  systemd.services.coder = {
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
  };
  # Lets Coder's Docker template run workspaces on the laptop.
  users.users.coder.extraGroups = [ "docker" ];
  systemd.tmpfiles.settings.coder."/var/lib/coder/env".f = {
    mode = "0600";
    user = "coder";
    group = "coder";
  };

  # reMarkable: drop a PDF or EPUB into ~/reMarkable and it shows up on the
  # tablet a moment later, through reMarkable's free cloud sync (no Connect
  # subscription needed). Sent files move to ~/reMarkable/Sent. Sign in once
  # first: run `rmapi` in a terminal and enter the code from
  # https://my.remarkable.com/device/browser/connect.
  systemd.services.remarkable-upload = {
    description = "Send files dropped into ~/reMarkable to the reMarkable tablet";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.rmapi
      pkgs.inotify-tools
    ];
    serviceConfig = {
      User = "pawel";
      Restart = "always";
      RestartSec = 30;
    };
    script = ''
      shopt -s nullglob nocaseglob
      cd /home/pawel/reMarkable
      upload() {
        for f in *.pdf *.epub; do
          # Skips empty files: browsers create one before the download lands.
          if [ -s "$f" ] && rmapi -ni put "./$f" /; then
            mv -- "$f" Sent/
          fi
        done
      }
      # Uploads whenever a file finishes copying or is moved in, and every hour
      # to retry files that didn't go through (say, before rmapi was signed
      # in). Events that come in during an upload wait in the pipe; once a
      # second goes by without one, a single upload covers them all.
      inotifywait --monitor --quiet --event close_write --event moved_to --format x . | {
        upload
        while read -r -t 3600 _ || [ $? -gt 128 ]; do
          while read -r -t 1 _; do :; done
          upload
        done
      }
    '';
  };
  systemd.tmpfiles.settings.remarkable =
    lib.genAttrs [ "/home/pawel/reMarkable" "/home/pawel/reMarkable/Sent" ] (_: {
      d = {
        mode = ":755";
        user = ":pawel";
        group = ":users";
      };
    });

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    config.services.coder.package # the `coder` command, for you and your agents
    curl
    gh
    git
    rmapi # reMarkable cloud from the terminal
    vim
  ];

  # The NixOS release this laptop was first installed with. Leave it as is,
  # even after moving nixpkgs to a newer release.
  system.stateVersion = "26.05";
}
