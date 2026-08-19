{ ... }:

# comet — MacBook Pro (Apple Silicon). macOS account: luna.
#
# Not yet adopted. To bring it under Nix, follow darwin/README.md:
#   sudo darwin-rebuild switch --flake ~/code/imlunahey/nixos-configs#comet
#
# No static IP here on purpose — a laptop roams networks, so it uses DHCP.
{
  networking.hostName = "comet";
  networking.computerName = "comet";
  networking.localHostName = "comet";

  # The macOS account nix-darwin applies user-scoped settings for.
  system.primaryUser = "luna";
  users.users.luna = {
    name = "luna";
    home = "/Users/luna";
  };

  # Attach the shared user environment to this machine's account.
  home-manager.users.luna = {
    imports = [ ../../home/common.nix ];
    home.username = "luna";
    home.homeDirectory = "/Users/luna";
  };
}
