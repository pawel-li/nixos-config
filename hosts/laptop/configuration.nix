{ config, lib, pkgs, ... }:

let
  # Each service's own address, http://<name>.laptop.local, and the port on
  # the laptop that nginx passes it on to. The addresses with a port, such as
  # http://laptop.local:2283, keep working too.
  webApps = {
    immich = 2283;
    jellyfin = 8096;
    navidrome = 4533;
    paperless = 28981;
    jobops = 3001;
    resume = 3002; # Reactive Resume
    coder = 3000;
    openwebui = 8081;
    homeassistant = 8123;
    rmfakecloud = 3004; # Immich's machine learning has 3003
  };
  webAppHosts = map (name: "${name}.laptop.local") (lib.attrNames webApps);
  # rmapi for rmfakecloud (further down) instead of reMarkable's cloud. It
  # keeps its sign-in in a file of its own, so `rmapi` stays signed in to
  # reMarkable's cloud.
  rmapiFakecloud = pkgs.writeShellScriptBin "rmapi-fakecloud" ''
    mkdir -p "$HOME/.config/rmapi"
    export RMAPI_HOST=http://127.0.0.1:3004
    export RMAPI_CONFIG="$HOME/.config/rmapi/rmfakecloud.conf"
    exec ${pkgs.rmapi}/bin/rmapi "$@"
  '';
in
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

  # Services here are for the home Wi-Fi: each one listens on every address,
  # and the firewall lets them answer only devices on the Wi-Fi network the
  # laptop is on, over IPv4 (the ports below). Nothing else gets through: not
  # the internet, not a network cable, not Docker containers (except Coder's,
  # further down). Other devices reach the services at laptop.local, which
  # avahi announces on the network. It announces only the IPv4 address, so
  # devices don't try the blocked IPv6 one first. nssmdns4 lets the laptop
  # itself use .local names too, so the same links work everywhere.
  services.avahi = {
    nssmdns4 = true;
    ipv6 = false;
    publish = {
      enable = true;
      addresses = true;
    };
  };
  networking.firewall.extraCommands =
    let
      wifiTcpPorts = [
        80 # Glance, through nginx
        8080 # Glance
        2283 # Immich
        8096 # Jellyfin
        4533 # Navidrome
        28981 # Paperless
        3001 # JobOps
        3002 # Reactive Resume
        3000 # Coder
        8081 # Open WebUI
        8123 # Home Assistant
        3004 # rmfakecloud
      ];
      wifiUdpPorts = [
        1900 # Jellyfin, for TVs and players that look for media servers
        7359 # Jellyfin, for its apps to find it
      ];
      portList = ports: lib.concatMapStringsSep "," toString ports;
    in
    # wl+ is any Wi-Fi interface. A service's openFirewall = true would open
    # its port on every network instead, so the services here leave it off.
    # docker0 is Docker's network: Coder's workspaces reach Coder (through
    # nginx on 80, or directly on 3000 for ones built before it moved to
    # coder.laptop.local) and its DNS server (53) through it.
    ''
      iptables -w -A nixos-fw -i wl+ -p tcp -m multiport --dports ${portList wifiTcpPorts} -j nixos-fw-accept
      iptables -w -A nixos-fw -i wl+ -p udp -m multiport --dports ${portList wifiUdpPorts} -j nixos-fw-accept
      iptables -w -A nixos-fw -i docker0 -p tcp -m multiport --dports 53,80,3000 -j nixos-fw-accept
      iptables -w -A nixos-fw -i docker0 -p udp --dport 53 -j nixos-fw-accept
    '';

  # Glance: the start page, at http://laptop.local (nginx below passes port 80
  # on to it) and http://laptop.local:8080. Links to every service below and
  # shows whether each one is up.
  services.glance = {
    enable = true;
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
                      url = "http://immich.laptop.local";
                      check-url = "http://127.0.0.1:2283/api/server/ping";
                      icon = "di:immich";
                    }
                    {
                      title = "Jellyfin";
                      url = "http://jellyfin.laptop.local";
                      check-url = "http://127.0.0.1:8096/health";
                      icon = "di:jellyfin";
                    }
                    {
                      title = "Navidrome";
                      url = "http://navidrome.laptop.local";
                      check-url = "http://127.0.0.1:4533/app/";
                      icon = "di:navidrome";
                    }
                    {
                      title = "Paperless";
                      url = "http://paperless.laptop.local";
                      check-url = "http://127.0.0.1:28981/accounts/login/";
                      icon = "di:paperless-ngx";
                    }
                    {
                      title = "JobOps";
                      url = "http://jobops.laptop.local";
                      check-url = "http://127.0.0.1:3001/health";
                      icon = "mdi:briefcase-search";
                    }
                    {
                      title = "Reactive Resume";
                      url = "http://resume.laptop.local";
                      check-url = "http://127.0.0.1:3002/api/health";
                      icon = "di:reactive-resume";
                    }
                    {
                      title = "Coder";
                      url = "http://coder.laptop.local";
                      check-url = "http://127.0.0.1:3000/healthz";
                      icon = "di:coder";
                    }
                    {
                      title = "Open WebUI";
                      url = "http://openwebui.laptop.local";
                      check-url = "http://127.0.0.1:8081/health";
                      icon = "di:open-webui";
                    }
                    {
                      title = "Home Assistant";
                      url = "http://homeassistant.laptop.local";
                      check-url = "http://127.0.0.1:8123/manifest.json";
                      icon = "di:home-assistant";
                    }
                    {
                      title = "rmfakecloud";
                      url = "http://rmfakecloud.laptop.local";
                      check-url = "http://127.0.0.1:3004/health";
                      icon = "di:remarkable.png";
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

  # Makes http://laptop.local/ show Glance, and http://<name>.laptop.local each
  # service in webApps at the top. Glance also answers when the laptop is
  # opened by its IP address or any other name.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    # Big uploads (videos, scans) and slow answers (AI models on the
    # processor) need more than nginx's usual 10 MB and 60 seconds.
    clientMaxBodySize = "0"; # no limit
    proxyTimeout = "600s";
    virtualHosts = {
      glance = {
        default = true;
        locations."/".proxyPass =
          "http://127.0.0.1:${toString config.services.glance.settings.server.port}";
      };
    }
    // lib.mapAttrs' (
      name: port:
      lib.nameValuePair "${name}.laptop.local" {
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          # Passes uploads straight on instead of saving them to disk first.
          extraConfig = "proxy_request_buffering off;";
        };
      }
    ) webApps;
  };

  # Announces the names in webApps on the Wi-Fi next to laptop.local, at the
  # laptop's current Wi-Fi address: avahi announces only the laptop's own
  # name by itself. Checks the address every 30 seconds and announces again
  # when it changes or a name dropped out.
  services.avahi.publish.userServices = true; # lets this service announce them
  systemd.services.mdns-names = {
    description = "Announce the services' .local names on the Wi-Fi";
    wantedBy = [ "multi-user.target" ];
    requires = [ "avahi-daemon.service" ];
    after = [ "avahi-daemon.service" ];
    path = [
      pkgs.avahi
      pkgs.iproute2
      pkgs.gawk
    ];
    serviceConfig = {
      DynamicUser = true;
      Restart = "always";
    };
    script = ''
      pids=()
      published=""
      announcing() {
        [ ''${#pids[@]} -gt 0 ] || return 1
        for pid in "''${pids[@]}"; do kill -0 "$pid" 2>/dev/null || return 1; done
      }
      while true; do
        address=$(ip -4 -o addr show scope global | awk '$2 ~ /^wl/ { sub("/.*", "", $4); print $4; exit }')
        if [ "$address" != "$published" ] || ! announcing; then
          [ ''${#pids[@]} -eq 0 ] || kill "''${pids[@]}" 2>/dev/null || true
          wait || true
          pids=()
          published=""
          if [ -n "$address" ]; then
            for name in ${lib.concatStringsSep " " webAppHosts}; do
              avahi-publish --address --no-reverse "$name" "$address" &
              pids+=($!)
            done
            published=$address
          fi
        fi
        sleep 30
      done
    '';
  };
  # Programs that look names up without avahi (Coder, and the Docker
  # containers on the laptop's network, which get a copy of /etc/hosts) find
  # the laptop's names here.
  networking.hosts."127.0.0.2" = lib.mkAfter ([ "laptop.local" ] ++ webAppHosts);

  # Immich: photos and videos, http://immich.laptop.local. The first visit asks
  # you to create the admin account; then install the Immich app on your phone
  # to back its photos up here (they're kept in /var/lib/immich). To include
  # the photos already in ~/Pictures, add /home/pawel/Pictures under
  # Administration → External Libraries. Immich sees that folder read-only and
  # nothing else in your home folder. (Immich itself comes from NixOS unstable
  # for now; see flake.nix.)
  services.immich = {
    enable = true;
    host = "::"; # every address, IPv4 and IPv6
  };
  systemd.services.immich-server.serviceConfig = {
    ProtectHome = lib.mkForce "tmpfs";
    BindReadOnlyPaths = [ "/home/pawel/Pictures" ];
  };

  # Jellyfin: films, series and music, http://jellyfin.laptop.local. The first
  # visit walks you through creating the admin account and adding ~/Videos and
  # ~/Music as libraries. Like Navidrome below, it runs as pawel and sees only
  # those two folders, read-only.
  services.jellyfin = {
    enable = true;
    user = "pawel";
    group = "users";
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
  # http://paperless.laptop.local. Create your login once with
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

  # Navidrome music server. Put music in ~/Music, then open
  # http://navidrome.laptop.local; the first visit asks you to create the admin
  # account. It runs as pawel so it can read whatever you copy there, and it
  # sees only that folder, read-only.
  services.navidrome = {
    enable = true;
    user = "pawel";
    group = "users";
    settings = {
      MusicFolder = "/home/pawel/Music";
      Address = "[::]"; # every address, IPv4 and IPv6
    };
  };
  # The module hides all of /home from Navidrome. "tmpfs" hides it too, but lets
  # the ~/Music folder above show through.
  systemd.services.navidrome.serviceConfig.ProtectHome = lib.mkForce "tmpfs";

  # JobOps: job search and applications, http://jobops.laptop.local. It searches
  # job boards, scores each offer against your CV, writes a CV for the ones you
  # pick and tracks where you applied. The first visit asks you to create your
  # account. It isn't packaged for NixOS, so it runs in Docker from the
  # project's own image and keeps its data in /var/lib/job-ops. Settings that
  # can't be made on the page, such as Gmail access, go in /var/lib/job-ops/env
  # (see the README). It uses the laptop's network directly, so the Wi-Fi-only
  # firewall rules apply to it: a port published the usual Docker way would
  # get past them.
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true; # weekly, clears out images replaced by updates
  };
  virtualisation.oci-containers = {
    backend = "docker";
    containers.job-ops = {
      image = "ghcr.io/dakheera47/job-ops:latest";
      networks = [ "host" ];
      volumes = [
        "/var/lib/job-ops/data:/app/data"
        "/var/lib/job-ops/codex-home:/app/codex-home"
        "/var/lib/job-ops/tectonic-cache:/root/.cache/Tectonic"
      ];
      environmentFiles = [ "/var/lib/job-ops/env" ];
      # Its CVs can go into Reactive Resume, below.
      environment.RXRESUME_URL = "http://resume.laptop.local";
    };
  };
  systemd.tmpfiles.settings.job-ops = {
    "/var/lib/job-ops".d.mode = "0700";
    "/var/lib/job-ops/env".f.mode = "0600";
  };

  # Reactive Resume: a resume builder, at http://resume.laptop.local. The first
  # visit asks you to create your account; then JobOps can write its CVs into
  # it (see the README). Like JobOps it runs in Docker on the laptop's network.
  # Its database is in the laptop's PostgreSQL, uploads go in
  # /var/lib/reactive-resume/data, and the secrets it needs in
  # /var/lib/reactive-resume/env, which the laptop writes itself the first
  # time, so they never end up in this repo.
  virtualisation.oci-containers.containers.reactive-resume = {
    image = "ghcr.io/reactive-resume/reactive-resume:v6"; # the newest 6.x
    networks = [ "host" ];
    environment = {
      PORT = "3002"; # Coder has 3000
      APP_URL = "http://resume.laptop.local"; # signing in works only at this address
    };
    volumes = [ "/var/lib/reactive-resume/data:/app/data" ];
    environmentFiles = [ "/var/lib/reactive-resume/env" ];
  };
  systemd.tmpfiles.settings.reactive-resume = {
    "/var/lib/reactive-resume".d.mode = "0700";
    # The app runs as uid 1000 inside the container.
    "/var/lib/reactive-resume/data".d = {
      mode = "0700";
      user = "1000";
      group = "1000";
    };
  };
  services.postgresql = {
    ensureDatabases = [ "reactive_resume" ];
    ensureUsers = [
      {
        name = "reactive_resume";
        ensureDBOwnership = true;
      }
    ];
  };
  # Writes the secrets the first time and gives the database user the password
  # from them: the container reaches PostgreSQL at 127.0.0.1, which asks for
  # one.
  systemd.services.reactive-resume-setup = {
    description = "Set up Reactive Resume's secrets and database password";
    requiredBy = [ "docker-reactive-resume.service" ];
    before = [ "docker-reactive-resume.service" ];
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
    path = [
      config.services.postgresql.package
      pkgs.openssl
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      env=/var/lib/reactive-resume/env
      if [ ! -s $env ]; then
        umask 077
        printf '%s\n' \
          "DATABASE_URL=postgresql://reactive_resume:$(openssl rand -hex 32)@127.0.0.1:5432/reactive_resume" \
          "AUTH_SECRET=$(openssl rand -hex 32)" \
          "ENCRYPTION_SECRET=$(openssl rand -hex 32)" > $env
      fi
      password=$(sed -n 's|^DATABASE_URL=postgresql://reactive_resume:\([^@]*\)@.*|\1|p' $env)
      echo "ALTER ROLE reactive_resume PASSWORD '$password'" |
        runuser -u postgres -- psql -v ON_ERROR_STOP=1 -q
    '';
  };

  # Moves each container to the newest release its image tag points to, once a
  # week. A container restarts only when its image changed.
  systemd.services.container-updates = {
    description = "Update the Docker containers to their latest releases";
    startAt = "weekly";
    path = [ config.virtualisation.docker.package ];
    serviceConfig.Type = "oneshot";
    script = ''
      update() {
        old=$(docker image inspect --format '{{.Id}}' "$1" || true)
        docker pull --quiet "$1" || return 1
        if [ "$(docker image inspect --format '{{.Id}}' "$1")" != "$old" ]; then
          systemctl restart "$2"
        fi
      }
      failed=0
    ''
    + lib.concatMapStrings (c: ''
      update ${c.image} ${c.serviceName}.service || failed=1
    '') (lib.attrValues config.virtualisation.oci-containers.containers)
    + ''
      exit $failed
    '';
  };

  # Coder: development machines ("workspaces") that you or an AI agent on the
  # home Wi-Fi start on demand, at http://coder.laptop.local. The first visit
  # asks you to create the admin account. Its Docker template runs workspaces
  # in containers here on the laptop. Its cloud templates won't work: machines
  # in the cloud can't reach Coder on the home network.
  services.coder = {
    enable = true;
    listenAddress = "[::]:3000"; # every address, IPv4 and IPv6
    # Where devices and workspaces reach Coder. Without it, Coder would open a
    # tunnel from a public address on the internet.
    accessUrl = "http://coder.laptop.local";
    # Coder's newest release (nixpkgs has an older one), with HashiCorp's own
    # build of the Terraform version it expects. Without one bundled, Coder
    # downloads Terraform itself, and 2.28 crashed doing so: its copy of
    # HashiCorp's signing key had expired. nixpkgs' Terraform isn't an option
    # either: its licence isn't free, so NixOS doesn't prebuild it and the
    # laptop would compile it. To update, change a version and set its hash to
    # "": the failed build prints the right one. Coder's
    # provisioner/terraform/install.go names the Terraform it wants.
    package =
      let
        terraform = pkgs.runCommand "terraform-1.16.7" {
          src = pkgs.fetchurl {
            url = "https://releases.hashicorp.com/terraform/1.16.7/terraform_1.16.7_linux_amd64.zip";
            hash = "sha256-VFTvz3/IfwwhExEbmlxxgvDKHG8PI6HhEKUHcKj+Rzs=";
          };
          nativeBuildInputs = [ pkgs.unzip ];
        } "unzip $src terraform && install -D terraform $out/bin/terraform";
      in
      (pkgs.coder.override { inherit terraform; }).overrideAttrs (final: prev: {
        version = "2.38.3";
        src = pkgs.fetchurl {
          url = "https://github.com/coder/coder/releases/download/v${final.version}/coder_${final.version}_linux_amd64.tar.gz";
          hash = "sha256-vwS2Qot2vgdqb+3ASdpGshydqsq7ZMLVmrXXDiw78dU=";
        };
      });
  };
  # Its module doesn't wait for the database it sets up.
  systemd.services.coder = {
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
  };
  # Lets Coder's Docker template run workspaces on the laptop.
  users.users.coder.extraGroups = [ "docker" ];
  # Workspace containers can't use avahi either. Docker points them at this
  # small DNS server, which answers laptop.local with the laptop's address on
  # Docker's network and passes every other name on to the laptop's own DNS
  # servers. The firewall rules at the top let workspaces reach it and Coder.
  virtualisation.docker.daemon.settings = {
    bip = "172.17.0.1/16"; # Docker's usual network, pinned for the line below
    dns = [ "172.17.0.1" ];
  };
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false; # the laptop itself keeps its DNS as it is
    settings = {
      interface = "docker0";
      bind-dynamic = true; # docker0 comes up after dnsmasq starts
      no-hosts = true; # /etc/hosts says 127.0.0.2, which is right only for the laptop
      address = "/laptop.local/172.17.0.1";
    };
  };

  # reMarkable: drop a PDF or EPUB into ~/reMarkable and it shows up on the
  # tablet a moment later, through reMarkable's free cloud sync (no Connect
  # subscription needed). Sent files move to ~/reMarkable/Sent. Sign in once
  # first: run `rmapi` in a terminal and enter the code from
  # https://my.remarkable.com/device/browser/connect. Once the tablet syncs
  # with rmfakecloud below instead, sign in there with `rmapi-fakecloud` and
  # files go to rmfakecloud from then on.
  systemd.services.remarkable-upload = {
    description = "Send files dropped into ~/reMarkable to the reMarkable tablet";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.rmapi
      rmapiFakecloud
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
        send=rmapi
        if [ -s "$HOME/.config/rmapi/rmfakecloud.conf" ]; then
          send=rmapi-fakecloud
        fi
        for f in *.pdf *.epub; do
          # Skips empty files: browsers create one before the download lands.
          if [ -s "$f" ] && $send -ni put "./$f" /; then
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

  # rmfakecloud: the reMarkable tablet's cloud, here on the laptop instead of
  # on reMarkable's servers, at http://rmfakecloud.laptop.local. The first
  # sign-in on the page creates the admin account with whatever username and
  # password you type. The tablet needs a small proxy installed over SSH to
  # sync here (see the README), and then syncs only on the home Wi-Fi. Its
  # files and accounts live in /var/lib/rmfakecloud.
  services.rmfakecloud = {
    enable = true;
    port = 3004; # Coder has 3000, Immich's machine learning 3003
    # Where the tablet finds it: the proxy on the tablet answers at this
    # address and passes everything on to the laptop. Newer tablet software
    # takes only https without a port here.
    storageUrl = "https://local.appspot.com";
  };

  # Open WebUI: a chat page for AI models, at http://openwebui.laptop.local. The
  # first visit asks you to create the admin account; anyone who signs up
  # after you waits for your approval. It runs models here on the laptop
  # through Ollama below, and online ones (OpenAI, OpenRouter, ...) once you
  # add their API key under Admin Panel → Settings → Connections. It runs in
  # Docker from the project's own image like JobOps: nixpkgs' licence check
  # counts Open WebUI as not free, so NixOS doesn't prebuild it and the laptop
  # would compile it after every update. Its data is in /var/lib/open-webui.
  virtualisation.oci-containers.containers.open-webui = {
    image = "ghcr.io/open-webui/open-webui:main"; # its newest release
    networks = [ "host" ];
    environment = {
      PORT = "8081"; # Glance has 8080
      WEBUI_URL = "http://openwebui.laptop.local";
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      # Keeps the sign-in key with the data, so a restart doesn't sign you out.
      WEBUI_SECRET_KEY_FILE = "/app/backend/data/.webui_secret_key";
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
    };
    volumes = [ "/var/lib/open-webui:/app/backend/data" ];
  };
  # Ollama runs AI models on the laptop, for Open WebUI and for JobOps (at
  # http://localhost:11434). It answers only the laptop itself. Download
  # models in Open WebUI under Admin Panel → Settings → Models. With no
  # graphics card to use, it runs them on the processor, so small models
  # (3-8B) work best.
  services.ollama.enable = true;

  # Home Assistant: smart home, at http://homeassistant.laptop.local. The
  # first visit walks you through creating your account. Devices it finds on
  # the Wi-Fi show up under Settings → Devices & services. This is Home
  # Assistant on its own, without the Supervisor, so there are no add-ons.
  # An integration whose Python packages aren't installed asks for them in
  # its error message: add its name to extraComponents.
  services.home-assistant = {
    enable = true;
    extraComponents = [
      # what the first-run setup sets up
      "default_config"
      "met"
      "esphome"
      "radio_browser"
      "google_translate"
      "shopping_list"
    ];
    config = {
      default_config = { };
      homeassistant.internal_url = "http://homeassistant.laptop.local";
      # Takes requests from nginx at homeassistant.laptop.local.
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
      # Where automations, scenes and scripts made on the page are saved.
      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";
    };
  };
  systemd.tmpfiles.settings.home-assistant =
    lib.genAttrs
      (map (name: "${config.services.home-assistant.configDir}/${name}.yaml") [
        "automations"
        "scenes"
        "scripts"
      ])
      (_: {
        f = {
          mode = "0644";
          user = "hass";
          group = "hass";
        };
      });

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    config.services.coder.package # the `coder` command, for you and your agents
    curl
    gh
    git
    rmapi # reMarkable cloud from the terminal
    rmapiFakecloud # the same for rmfakecloud
    vim
  ];

  # The NixOS release this laptop was first installed with. Leave it as is,
  # even after moving nixpkgs to a newer release.
  system.stateVersion = "26.05";
}
