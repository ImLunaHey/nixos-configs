{
  description = "Luna's Nix configurations (NixOS servers + macOS/nix-darwin)";
  inputs = {
    # NixOS servers track nixos-unstable.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # macOS tracks nixpkgs-unstable, which is what nix-darwin's master branch
    # requires (their release numbers must match). Kept separate so the servers'
    # channel is unaffected.
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Pulsar dogfood advances independently so Nova, Gilbert, and Void are never
    # changed merely to update the control-plane host.
    anvil-dogfood = {
      url = "git+http://100.117.220.119:3001/git/luna/anvil?ref=main";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-darwin, sops-nix, nix-minecraft, disko, nix-darwin, home-manager, anvil-dogfood, ... }: {
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
          anvil-dogfood.darwinModules.default
        ];
      };

      # MacBook Pro (not yet adopted — see darwin/README.md)
      comet = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./darwin/common.nix
          ./darwin/comet
          home-manager.darwinModules.home-manager
        ];
      };
    };
  };
}
