{ ... }:
{
  # Run the client alongside Tailscale until every peer and route has moved.
  services.netbird = {
    useRoutingFeatures = "client";

    clients.default = {
      name = "netbird";
      interface = "wt0";
      port = 51820;
      hardened = true;
      config = {
        ManagementURL = "https://netbird.flaked.org:443";
        AdminURL = "https://netbird.flaked.org:443";
      };
    };
  };

  networking.firewall.trustedInterfaces = [ "wt0" ];
  users.users.luna.extraGroups = [ "netbird" ];
}
