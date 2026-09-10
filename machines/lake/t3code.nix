{ config, pkgs, t3codePkgs, ... }:
let
  user = config.users.users.luna;
  codeDirectory = "${user.home}/code";
  tailscaleAddress = "100.94.132.48";
  port = 3773;
in
{
  environment.systemPackages = with t3codePkgs; [
    t3code
    codex
    gh
    nodejs_24
    ripgrep
  ];

  # Lake's root filesystem (including /home) is on the 2 TB NVMe SSD.
  systemd.tmpfiles.rules = [
    "d ${codeDirectory} 0750 luna ${user.group} -"
    "d ${user.home}/.t3 0700 luna ${user.group} -"
  ];

  systemd.services.t3code = {
    description = "T3 Code coding workspace";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "tailscale-autoauth.service"
      "systemd-tmpfiles-setup.service"
    ];
    wants = [ "network-online.target" "tailscale-autoauth.service" ];
    unitConfig = {
      RequiresMountsFor = [ user.home ];
      # Keep retrying if the Tailscale address is unavailable during startup.
      StartLimitIntervalSec = 0;
    };

    environment.HOME = user.home;
    path = with pkgs; [
      bashInteractive
      coreutils
      findutils
      git
      gnugrep
      gnused
      t3codePkgs.nodejs_24
      openssh
      ripgrep
    ];

    serviceConfig = {
      User = "luna";
      Group = user.group;
      WorkingDirectory = codeDirectory;
      # Use the server CLI explicitly: the package's default executable is GUI.
      ExecStart = "${t3codePkgs.t3code}/bin/t3 serve --host ${tailscaleAddress} --port ${toString port} --base-dir ${user.home}/.t3";
      Restart = "always";
      RestartSec = "5s";
      UMask = "0027";
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
