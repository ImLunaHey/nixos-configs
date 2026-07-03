{
  description = "Luna's Nix configurations (NixOS servers + macOS/nix-darwin)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, sops-nix, nix-minecraft, disko, nix-darwin, home-manager, ... }: {
    nixosConfigurations = {
      nova = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common.nix
          ./machines/nova
          sops-nix.nixosModules.sops
        ];
      };

      gilbert = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common.nix
          ./machines/gilbert
          sops-nix.nixosModules.sops
          nix-minecraft.nixosModules.minecraft-servers
        ];
      };

      void = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common.nix
          ./machines/void
          sops-nix.nixosModules.sops
          disko.nixosModules.disko
        ];
      };
    };

    # macOS hosts, managed with nix-darwin + home-manager.
    # Rebuild with: darwin-rebuild switch --flake .#pulsar
    darwinConfigurations = {
      # Mac mini
      pulsar = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./darwin/common.nix
          ./darwin/pulsar
          home-manager.darwinModules.home-manager
        ];
      };
    };
  };
}
