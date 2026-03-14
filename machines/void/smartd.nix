{ config, pkgs, lib, ... }:
let
  notifyScript = pkgs.writeShellScript "smartd-notify-gotify" ''
    ${pkgs.curl}/bin/curl -sf \
      -F "title=SMART Alert: $SMARTD_DEVICE ($SMARTD_FAILTYPE)" \
      -F "message=$SMARTD_MESSAGE" \
      -F "priority=8" \
      "https://gotify.flaked.org/message?token=$(cat ${config.sops.secrets.gotify_upgrade_token.path})" \
      || true
  '';
in
{
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.monitored = lib.concatStringsSep " " [
      "-a"             # monitor all attributes
      "-o on"          # automatic offline tests
      "-S on"          # attribute autosave
      "-s (S/../.././02|L/../../6/03)"  # short test daily 2am, long test Saturdays 3am
      "-W 4,45,55"     # warn at 45°C, critical at 55°C
      "-M exec ${notifyScript}"
    ];
  };
}
