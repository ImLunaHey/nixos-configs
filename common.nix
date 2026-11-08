{ ... }:
{
  # Compatibility entry point for Luna's existing hosts. Reusable consumers
  # should import profiles/base.nix directly and supply their own options.
  # Keep the existing D-Bus implementation during live NixOS upgrades.
  services.dbus.implementation = "dbus";

  imports = [
    ./profiles/base.nix
    ./personal.nix
  ];
}
