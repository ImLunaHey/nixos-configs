{ pkgs, lib, brrrNotify, ... }:
let
  notifyScript = pkgs.writeShellScript "smartd-notify-brrr" ''
    ${brrrNotify} \
      "SMART Alert: $SMARTD_DEVICE ($SMARTD_FAILTYPE)" \
      "$SMARTD_MESSAGE" \
      time-sensitive warm_soft_error smartd
  '';
in
{
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.monitored = lib.concatStringsSep " " [
      "-a"
      "-o on"
      "-S on"
      "-s (S/../.././02|L/../../6/03)"
      "-W 4,45,55"
      "-M exec ${notifyScript}"
    ];
  };
}
