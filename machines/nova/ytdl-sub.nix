{ pkgs, lib, ... }:
let
  # ---------------------------------------------------------------------------
  # Edit machines/nova/ytdl-sub-channels.nix to add channels / playlists / music.
  # Everything below just turns that simple list into ytdl-sub's two YAML files.
  # ---------------------------------------------------------------------------
  subs = import ./ytdl-sub-channels.nix;

  # Render one entry under a preset:
  #   "url" string      -> override mode (~), name taken from the source's own title (autoVar)
  #   { name; url; }     -> simple mode, name = the one you gave
  renderEntry = keyPrefix: nameVar: autoVar: i: entry:
    if builtins.isString entry then
      "  \"~${keyPrefix}-${toString i}\":\n"
      + "    url: \"${entry}\"\n"
      + "    ${nameVar}: \"${autoVar}\""
    else
      "  \"${entry.name}\": \"${entry.url}\"";

  # Emit a preset block only when it has entries (an empty mapping is invalid YAML).
  renderGroup = { preset, keyPrefix, nameVar, autoVar, items }:
    lib.optionalString (items != [])
      ("\"${preset}\":\n"
       + lib.concatStringsSep "\n" (lib.imap0 (renderEntry keyPrefix nameVar autoVar) items)
       + "\n\n");

  subscriptionsHeader =
    "__preset__:\n"
    + "  overrides:\n"
    + "    tv_show_directory: \"/tv_shows\"\n"
    + "    music_directory: \"/music\"\n\n";

  subscriptionsYaml = pkgs.writeText "subscriptions.yaml" (
    subscriptionsHeader
    + renderGroup { preset = "Jellyfin TV Show by Date";    keyPrefix = "channel";  nameVar = "tv_show_name"; autoVar = "{channel}";           items = subs.channels; }
    + renderGroup { preset = "Jellyfin TV Show Collection"; keyPrefix = "playlist"; nameVar = "tv_show_name"; autoVar = "{playlist_title}";    items = subs.playlists; }
    + renderGroup { preset = "YouTube Releases";            keyPrefix = "music";    nameVar = "track_artist"; autoVar = "{playlist_uploader}"; items = subs.music; }
  );

  configYaml = pkgs.writeText "config.yaml" ''
    configuration:
      working_directory: "/config/.working"
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/ytdl-sub        0755 root root -"
    "d /var/lib/ytdl-sub/config 0755 100000 100000 -"
  ];

  virtualisation.oci-containers.containers.ytdl-sub = {
    # Headless: runs `ytdl-sub sub` on a cron schedule. No web UI / port exposed.
    image = "ghcr.io/jmbannon/ytdl-sub:latest";
    volumes = [
      "/var/lib/ytdl-sub/config:/config"
      "${configYaml}:/config/config.yaml:ro"
      "${subscriptionsYaml}:/config/subscriptions.yaml:ro"
      "/mnt/media/youtube:/tv_shows"
      "/mnt/media/music:/music"
    ];
    environment = {
      # PUID/PGID 0 -> container root -> host uid 100000 under userns-remap,
      # matching the /config dir and the media dirs' ownership on void
      PUID = "0";
      PGID = "0";
      TZ = "Europe/London";
      CRON_SCHEDULE = "0 */6 * * *"; # check subscriptions for new content every 6h
      CRON_RUN_ON_START = "true";
      UPDATE_YT_DLP_ON_START = "stable"; # yt-dlp breaks often as YouTube changes
    };
  };
}
