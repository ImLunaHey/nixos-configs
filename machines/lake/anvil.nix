{
  config,
  pkgs,
  ...
}:
let
  tailscaleAddress = "100.94.132.48";
  httpPort = 3001;
  sshPort = 2222;
in
{
  sops.secrets.anvil_auth_secret = {
    owner = "anvil";
    group = "anvil";
    mode = "0400";
    restartUnits = [ "anvil.service" ];
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    ensureDatabases = [ "anvil" ];
    ensureUsers = [
      {
        name = "anvil";
        ensureDBOwnership = true;
      }
    ];
  };

  services.anvil = {
    enable = true;
    stateDirectory = "/var/lib/anvil";
    bindAddress = "${tailscaleAddress}:${toString httpPort}";
    databaseUrl = "postgresql:///anvil?host=/run/postgresql";
    openFirewall = true;
    auth = {
      mode = "required";
      secretFile = config.sops.secrets.anvil_auth_secret.path;
      publicUrl = "http://${tailscaleAddress}:${toString httpPort}";
      trustedOrigins = [
        "http://${tailscaleAddress}:${toString httpPort}"
        "http://127.0.0.1:${toString httpPort}"
        "http://localhost:${toString httpPort}"
      ];
    };
    ssh.bindAddress = "${tailscaleAddress}:${toString sshPort}";
    backup = {
      enable = true;
      directory = "/mnt/storage/backups/anvil";
      schedule = "daily";
      serverUrl = "http://${tailscaleAddress}:${toString httpPort}";
    };
  };

  services.anvil-agent = {
    enable = true;
    serverUrl = "http://${tailscaleAddress}:${toString httpPort}";
    name = "local";
    address = tailscaleAddress;
    root = "/var/lib/anvil-agent";
  };

  systemd.services.anvil = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };
}
