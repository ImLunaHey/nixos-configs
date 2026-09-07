{
  description = "Reusable NixOS modules and templates";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosModules = {
      default = ../profiles/base.nix;
      base = ../profiles/base.nix;
    };

    templates.default = {
      path = ../templates/default;
      description = "A reusable NixOS server configuration";
    };
  };
}
