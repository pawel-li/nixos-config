{
  description = "NixOS config for Pawel's laptop. Pushing to main updates the laptop.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for Immich and Home Assistant (see below). Straight from the NixOS
    # channel server, which serves the same tested commits as the
    # nixos-unstable branch on GitHub.
    nixpkgs-unstable.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }: {
    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      modules = [
        ./hosts/laptop/configuration.nix
        ./modules/git-deploy.nix
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          # The commit this system was built from. git-deploy compares it with GitHub.
          system.configurationRevision = self.rev or self.dirtyRev or "dirty";
          # 26.05 ships Immich 2.x, which has known security holes and gets no
          # more updates; unstable has Immich 3. After moving to NixOS 26.11,
          # delete this line, the Home Assistant one below and the
          # nixpkgs-unstable input.
          services.immich.package = nixpkgs-unstable.legacyPackages.x86_64-linux.immich;
          # 26.05 ships Home Assistant 2026.5, which can't sign in to Ecovacs:
          # Ecovacs changed its login in July 2026 and answers "Please update
          # to the latest version" (code 1013). 2026.10 and later sign in, with
          # a code Ecovacs emails. Skipping its tests as NixOS does for its own
          # Home Assistant, or the laptop would spend hours running them.
          services.home-assistant.package =
            nixpkgs-unstable.legacyPackages.x86_64-linux.home-assistant.overrideAttrs {
              doInstallCheck = false;
            };
        }
      ];
    };
  };
}
