{ config, lib, pkgs, ... }:
let
  cfg = config.services.anvil-deployment-host;
  agentRoot = "/var/lib/anvil-agent";
  deploymentKey = "luna-anvil-anvil-canary-${cfg.environment}";
  activationPath = "${agentRoot}/active/${deploymentKey}";
  environmentFile = "${agentRoot}/runtime/${deploymentKey}.env";
in {
  options.services.anvil-deployment-host = {
    enable = lib.mkEnableOption "Anvil deployment agent and canary service";
    environment = lib.mkOption {
      type = lib.types.enum [ "staging" "production" ];
      description = "Canary environment activated on this host.";
    };
    address = lib.mkOption {
      type = lib.types.str;
      description = "Tailscale address reported to the Anvil control plane.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.anvil-agent = {
      enable = true;
      serverUrl = "http://100.117.220.119:3001";
      name = config.networking.hostName;
      address = cfg.address;
      root = agentRoot;
      maxDeployments = 1;
      sopsAgeKeyFile = "${agentRoot}/sops-age-key";
      activations.anvil-canary = {
        path = activationPath;
        unit = "anvil-canary.service";
        inherit environmentFile;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${agentRoot}/canary-state 0700 anvil-agent anvil-agent -"
      "d ${agentRoot}/secrets/canary 0700 anvil-agent anvil-agent -"
      "f ${agentRoot}/secrets/canary/state-directory 0600 anvil-agent anvil-agent - ${agentRoot}/canary-state"
    ];

    systemd.services.anvil-agent-identity = {
      description = "Install the host-owned SOPS age identity for Anvil";
      requiredBy = [ "anvil-agent.service" ];
      before = [ "anvil-agent.service" ];
      path = [ pkgs.coreutils ];
      script = ''
        install -o anvil-agent -g anvil-agent -m 0600 \
          /run/secrets.d/age-keys.txt ${agentRoot}/sops-age-key
      '';
      serviceConfig.Type = "oneshot";
    };
    systemd.services.anvil-agent = {
      requires = [ "anvil-agent-identity.service" ];
      after = [ "anvil-agent-identity.service" ];
    };

    systemd.services.anvil-canary = {
      description = "Anvil remotely deployed canary";
      environment = {
        ANVIL_CANARY_BIND = "0.0.0.0:3100";
        HOSTNAME = config.networking.hostName;
      };
      serviceConfig = {
        User = "anvil-agent";
        Group = "anvil-agent";
        ExecStart = "${activationPath}/bin/anvil-canary";
        Restart = "on-failure";
        RestartSec = 2;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ agentRoot ];
      };
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3100 ];
  };
}
