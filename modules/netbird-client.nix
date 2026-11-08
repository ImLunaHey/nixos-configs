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
        # The client config serializes Go's url.URL as an object.
        ManagementURL = { Scheme = "https"; Host = "netbird.flaked.org:443"; };
        AdminURL = { Scheme = "https"; Host = "netbird.flaked.org:443"; };
      };
    };
  };

  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 22 ];
  users.users.luna.extraGroups = [ "netbird" ];
}
