{ ... }:

# pulsar — Mac mini (Apple Silicon). macOS account: xo.
{
  imports = [
    ./networking.nix
  ];

  networking.hostName = "pulsar";
  networking.computerName = "pulsar";
  networking.localHostName = "pulsar";

  # The macOS account nix-darwin applies user-scoped settings (defaults,
  # homebrew) for. Must be an account that already exists on the machine.
  system.primaryUser = "xo";
  users.users.xo = {
    name = "xo";
    home = "/Users/xo";
  };

  # Attach the shared user environment to this machine's account.
  home-manager.users.xo = {
    imports = [ ../../home/common.nix ];
    home.username = "xo";
    home.homeDirectory = "/Users/xo";
  };
}
