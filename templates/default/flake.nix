{
  description = "A NixOS host using the reusable homelab base profile";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    homelab.url = "github:ImLunaHey/nixos-configs";
    homelab.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { nixpkgs, homelab, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ homelab.nixosModules.default ./configuration.nix ];
    };
  };
}
