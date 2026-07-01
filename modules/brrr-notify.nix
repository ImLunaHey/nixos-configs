# Shared brrr.now push-notification helper.
#
# Exposes `brrrNotify` as a module arg so any module can send a notification:
#
#   ${brrrNotify} "Title" "Message body"
#   ${brrrNotify} "Title" "Message body" time-sensitive warm_soft_error smartd
#
# Positional args: <title> <message> [interruption_level] [sound] [thread_id]
# Reads the bearer token from the sops `brrr_token` secret (declared per host).
{ config, pkgs, ... }:

{
  _module.args.brrrNotify = pkgs.writeShellScript "brrr-notify" ''
    title="$1"
    message="$2"
    level="''${3:-active}"
    sound="''${4:-default}"
    thread="''${5:-nixos}"

    ${pkgs.jq}/bin/jq -nc \
      --arg title "$title" \
      --arg message "$message" \
      --arg level "$level" \
      --arg sound "$sound" \
      --arg thread "$thread" \
      '{title: $title, message: $message, thread_id: $thread, sound: $sound, interruption_level: $level}' \
      | ${pkgs.curl}/bin/curl -sf \
        -H "Authorization: Bearer $(cat ${config.sops.secrets.brrr_token.path})" \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "https://api.brrr.now/v1/send" \
      || true
  '';
}
