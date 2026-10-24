{
  description = "NixOS config for Pawel's laptop. Pushing to main updates the laptop.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      modules = [
        ./hosts/laptop/configuration.nix
        ./modules/git-deploy.nix
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          # The commit this system was built from. git-deploy compares it with GitHub.
          system.configurationRevision = self.rev or self.dirtyRev or "dirty";
        }
      ];
    };
  };
}
