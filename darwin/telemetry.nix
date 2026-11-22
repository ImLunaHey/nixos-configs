{ config, pkgs, ... }:
let
  name = config.networking.hostName;
  user = config.system.primaryUser;
  collector = pkgs.callPackage ../machines/gateway/packages/hardware-telemetry { };
  address = if name == "pulsar" then "10.0.0.107" else "10.0.0.21";
in {
  launchd.user.agents.hardware-telemetry = {
    serviceConfig = {
      Label = "net.luna.hardware-telemetry";
      ProgramArguments = [ "${collector}/bin/hardware-telemetry" ];
      EnvironmentVariables = {
        METRICS_NAME = name;
        METRICS_INTERFACE = if name == "pulsar" then "en1" else "en0";
        METRICS_BIND = address;
        METRICS_ALLOWED_CLIENTS = "10.0.0.161,100.75.169.97,127.0.0.1";
      };
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 5;
      StandardErrorPath = "/Users/${user}/Library/Logs/hardware-telemetry.log";
    };
  };
}
