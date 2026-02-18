{
  description = "Luna's NixOS configurations";
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
  };

  outputs = { self, nixpkgs, sops-nix, nix-minecraft, ... }: {
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
    };
  };
}