{ ... }:
{
  # Compatibility entry point for Luna's existing hosts. Reusable consumers
  # should import profiles/base.nix directly and supply their own options.
  imports = [
    ./profiles/base.nix
    ./personal.nix
  ];
}
