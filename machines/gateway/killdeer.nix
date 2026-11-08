{ pkgs, ... }:

{
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;

  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;
  services.cloud-init.settings = {
    datasource_list = [ "NoCloud" ];
  };
  systemd.services.cloud-init-local.restartIfChanged = false;
  systemd.services.cloud-init.restartIfChanged = false;
  systemd.services.cloud-config.restartIfChanged = false;
  systemd.services.cloud-final.restartIfChanged = false;

  services.qemuGuest.enable = true;
  services.openssh.enable = true;

  users.groups.sudo = {};
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    cloud-init
  ];
}
