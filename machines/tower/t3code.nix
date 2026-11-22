{ config, pkgs, t3codePkgs, ... }:
let
  user = config.users.users.luna;
  t3code = t3codePkgs.callPackage ../../packages/t3code { };
  codex = t3codePkgs.callPackage ../../packages/codex { };
  tools = [ codex ] ++ (with t3codePkgs; [ gh nodejs_24 ripgrep ]);
in
{
  environment.systemPackages = [ t3code ] ++ tools;

  # Runtime dependencies for T3's downloaded browser preview binary.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      alsa-lib at-spi2-core dbus expat glib libgbm libx11 libxcb
      libxcomposite libxdamage libxext libxfixes libxkbcommon libxrandr
      nspr nss systemd
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${user.home}/code 0750 luna ${user.group} -"
    "d ${user.home}/.t3 0700 luna ${user.group} -"
  ];

  systemd.services.t3code = {
    description = "T3 Code coding workspace";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "systemd-tmpfiles-setup.service" ];
    wants = [ "network-online.target" ];
    unitConfig = {
      RequiresMountsFor = [ user.home ];
      StartLimitIntervalSec = 0;
    };
    environment.HOME = user.home;
    path = tools ++ (with pkgs; [
      bashInteractive coreutils findutils git gnugrep gnused openssh
    ]);
    serviceConfig = {
      User = "luna";
      Group = user.group;
      WorkingDirectory = "${user.home}/code";
      # Direct access is allowed only on tailscale0; loopback also permits
      # SSH forwarding and T3 Connect pairing before VPN enrolment.
      ExecStart = "${t3code}/bin/t3 serve --host 0.0.0.0 --port 3773 --base-dir ${user.home}/.t3";
      Restart = "always";
      RestartSec = "5s";
      UMask = "0027";
    };
  };
}
