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
  # laptop.local, which the line below announces on the network.
  services.avahi.publish = {
    enable = true;
    addresses = true;
  };

  # Navidrome music server. Put music in ~/Music, then open
  # http://laptop.local:4533 (or http://localhost:4533 on the laptop itself);
  # the first visit asks you to create the admin account. It runs as pawel so
  # it can read whatever you copy there, and it sees only that folder, read-only.
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
