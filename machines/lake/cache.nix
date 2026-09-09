{ config, ... }:
let
  tailscaleAddress = "100.94.132.48";
  cachePort = 5000;
in
{
  sops.secrets.harmonia_signing_key = {
    restartUnits = [ "harmonia.service" ];
  };

  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ config.sops.secrets.harmonia_signing_key.path ];
    settings.bind = "${tailscaleAddress}:${toString cachePort}";
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cachePort ];
}
