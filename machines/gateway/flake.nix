{
  description = "Killdeer public gateway bootstrap (independent of Lake)";
  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
  inputs.fleet-monitor = { url = "github:ImLunaHey/fleet-monitor/v0.5.0"; inputs.nixpkgs.follows = "nixpkgs"; };
  outputs = inputs@{ nixpkgs, ... }: {
    nixosConfigurations.gateway = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ inputs.fleet-monitor.nixosModules.default ./configuration.nix ];
    };
  };
}
