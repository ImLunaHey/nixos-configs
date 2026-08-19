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

  services.anvil = {
    enable = true;
    user = "xo";
    stateDirectory = "/Users/xo/.local/state/anvil";
    repositoryDirectory = "/Users/xo/.local/state/anvil/repositories";
    ciDirectory = "/Users/xo/.local/state/anvil/ci";
    logDirectory = "/Users/xo/.local/state/anvil/logs";
    activationPath = "/Users/xo/.local/state/anvil/agent/active/luna-anvil-anvil-dogfood";
    bindAddress = "0.0.0.0:3001";
    postgresql = {
      enable = true;
      dataDirectory = "/Users/xo/.local/state/anvil/postgresql";
      socketDirectory = "/Users/xo/.local/state/anvil/postgresql-socket";
      port = 55432;
      database = "anvil";
    };
    backup = {
      enable = true;
      directory = "/Users/xo/.local/state/anvil-backups";
      intervalSeconds = 86400;
      serverUrl = "http://127.0.0.1:3001";
    };
  };

  services.anvil-agent = {
    enable = true;
    user = "xo";
    serverUrl = "http://127.0.0.1:3001";
    name = "local";
    address = "100.117.220.119";
    root = "/Users/xo/.local/state/anvil/agent";
    logDirectory = "/Users/xo/.local/state/anvil/logs";
  };

  # Attach the shared user environment to this machine's account.
  home-manager.users.xo = {
    imports = [ ../../home/common.nix ];
    home.username = "xo";
    home.homeDirectory = "/Users/xo";
  };
}
