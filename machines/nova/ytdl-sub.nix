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

  # A "show" is { name; seasons = [ url ... ]; }. The TV Show Collection preset
  # takes each season playlist as s01_url, s02_url, ... -> Season 01, Season 02, ...
  # The "~" prefix is override mode; the name itself becomes the show (tv_show_name).
  pad2 = n: if n < 10 then "0${toString n}" else toString n;
  # A season is a bare URL, or { name; url; } to give it a title (s0N_name).
  renderSeason = n: season:
    if builtins.isString season then
      "    s${pad2 n}_url: \"${season}\""
    else
      "    s${pad2 n}_name: \"${season.name}\"\n"
      + "    s${pad2 n}_url: \"${season.url}\"";
  renderShow = show:
    "  \"~${show.name}\":\n"
    + lib.concatStringsSep "\n" (lib.imap1 renderSeason show.seasons);
  showsBlock = shows:
    lib.optionalString (shows != [])
      ("\"Jellyfin TV Show Collection\":\n"
       + lib.concatStringsSep "\n" (map renderShow shows)
       + "\n\n");

  subscriptionsHeader =
    "__preset__:\n"
    + "  overrides:\n"
    + "    tv_show_directory: \"/tv_shows\"\n"
    + "    music_directory: \"/music\"\n\n";

  subscriptionsYaml = pkgs.writeText "subscriptions.yaml" (
    subscriptionsHeader
    + renderGroup { preset = "Jellyfin TV Show by Date"; keyPrefix = "channel"; nameVar = "tv_show_name"; autoVar = "{channel}";           items = subs.channels; }
    + showsBlock subs.shows
    + renderGroup { preset = "YouTube Releases";         keyPrefix = "music";   nameVar = "track_artist"; autoVar = "{playlist_uploader}"; items = subs.music; }
  );

  configYaml = pkgs.writeText "config.yaml" ''
    configuration:
      working_directory: "/config/.working"
  '';

  # The image's cron wrapper does `cd /config; . /config/cron` on CRON_SCHEDULE
  # and on start, so the script runs with cwd /config where config.yaml +
  # subscriptions.yaml live and a bare `ytdl-sub sub` finds them. The stock
  # /config/cron is a no-op warning; this replaces it.
  cronScript = pkgs.writeText "ytdl-sub-cron" ''
    ytdl-sub sub
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
      "${cronScript}:/config/cron:ro"
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
