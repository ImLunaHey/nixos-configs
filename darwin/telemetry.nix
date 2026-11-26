{ config, ... }:
let name = config.networking.hostName; in {
  services.fleet-monitor = {
    enable = true;
    processes.enable = true;
    mode = "agent";
    inherit name;
    interface = if name == "pulsar" then "en1" else "en0";
    listenAddress = if name == "pulsar" then "10.0.0.107" else "10.0.0.21";
    allowedClients = [ "10.0.0.161" "100.75.169.97" "127.0.0.1" ];
  };
}
