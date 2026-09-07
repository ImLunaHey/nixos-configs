{ ... }:
{
  networking.hostName = "example";
  homelabBase = {
    user = {
      name = "admin";
      authorizedKeys = [ "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY" ];
      passwordlessSudo = true;
    };
    ssh.enable = true;
    vpn.provider = "none"; # "tailscale" and "netbird" are also supported.
  };
  system.stateVersion = "26.05";
}
