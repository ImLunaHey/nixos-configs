{ ... }:
{
  # Run NetBird alongside Tailscale until the migration is complete. The
  # client's state, including its one-time enrollment, persists in
  # /var/lib/netbird.
  services.netbird = {
    useRoutingFeatures = "client";

    clients.default = {
      name = "netbird";
      interface = "wt0";
      port = 51820;
      hardened = true;
    };
  };

  networking.firewall.trustedInterfaces = [ "wt0" ];
  users.users.luna.extraGroups = [ "netbird" ];
}
