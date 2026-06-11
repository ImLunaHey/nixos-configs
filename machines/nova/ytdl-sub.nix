{ pkgs, lib, ... }:
let
  # ---------------------------------------------------------------------------
  # Edit machines/nova/ytdl-sub-channels.nix to add channels / playlists / music.
  # Everything below just turns that simple list into ytdl-sub's two YAML files.
  # ---------------------------------------------------------------------------
  subs = import ./ytdl-sub-channels.nix;

  # Best-effort static show/artist name from a YouTube URL — the @handle if
  # present, else the last path segment. Must be static: ytdl-sub output dirs
  # can't depend on per-video variables like {channel}.
  deriveName = url:
    let
      parts = lib.filter (s: s != "") (lib.splitString "/" (lib.head (lib.splitString "?" url)));
      atParts = lib.filter (lib.hasPrefix "@") parts;
    in if atParts != [] then lib.removePrefix "@" (lib.head atParts) else lib.last parts;

  # Render one entry under a preset. An entry is either a bare URL string
  # (named from its @handle) or an attrset:
  #   { url; name?; description?; limit?; }
  #     name        -> override the derived name (channel/artist)
  #     description -> true: use the video's YouTube description as the plot
  #     limit       -> only grab the first N items (for huge channels)
  renderEntry = nameVar: entry:
    let
      e = if builtins.isString entry then { url = entry; } else entry;
      nameVal = if e ? name then e.name else deriveName e.url;
      lines = [
        "  \"~${nameVal}\":"
        "    url: \"${e.url}\""
        "    ${nameVar}: \"${nameVal}\""
      ]
      ++ lib.optional (e.description or false) "    episode_plot: \"{description}\""
      # channel_limit is an override variable consumed by the "Limited Channel"
      # preset's ytdl_options (plugin options can't live in a ~ override block).
      ++ lib.optional (e ? limit) "    channel_limit: \"${toString e.limit}\"";
    in lib.concatStringsSep "\n" lines;

  # Emit a preset block only when it has entries (an empty mapping is invalid YAML).
  renderGroup = { preset, nameVar, items }:
    lib.optionalString (items != [])
      ("\"${preset}\":\n"
       + lib.concatStringsSep "\n" (map (renderEntry nameVar) items)
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
  # A show also takes optional `genre` and `description` (true -> use the
  # videos' YouTube descriptions as plots; default is no plot at all).
  renderShow = show:
    lib.concatStringsSep "\n" ([
      "  \"~${show.name}\":"
    ]
    ++ lib.optional (show ? genre) "    tv_show_genre: \"${show.genre}\""
    ++ lib.optional (show.description or false) "    episode_plot: \"{description}\""
    ++ lib.imap1 renderSeason show.seasons);
  showsBlock = shows:
    lib.optionalString (shows != [])
      ("\"Jellyfin TV Show Collection\":\n"
       + lib.concatStringsSep "\n" (map renderShow shows)
       + "\n\n");

  subscriptionsHeader =
    "__preset__:\n"
    + "  overrides:\n"
    + "    tv_show_directory: \"/tv_shows\"\n"
    + "    music_directory: \"/music\"\n"
    # Clean up Jellyfin display: episode title = the raw YouTube title (drop the
    # "<date> - " prefix), no plot by default (per-entry `description = true` opts
    # back in), and number collection episodes by playlist position not upload date.
    + "    episode_title: \"{title}\"\n"
    + "    episode_plot: \"\"\n"
    + "    tv_show_collection_episode_ordering: \"playlist-index\"\n"
    + "    tv_show_genre: \"YouTube\"\n\n";

  subscriptionsYaml = pkgs.writeText "subscriptions.yaml" (
    subscriptionsHeader
    + renderGroup { preset = "Limited Channel"; nameVar = "tv_show_name"; items = subs.channels; }
    + showsBlock subs.shows
    + renderGroup { preset = "YouTube Releases"; nameVar = "track_artist"; items = subs.music; }
  );

  configYaml = pkgs.writeText "config.yaml" ''
    configuration:
      working_directory: "/config/.working"
    presets:
      # "Jellyfin TV Show by Date" plus a download cap. ytdl_options can use the
      # {channel_limit} override variable here (in a preset) but not in a ~ block.
      "Limited Channel":
        preset:
          - "Jellyfin TV Show by Date"
        ytdl_options:
          playlist_items: "1:{channel_limit}"
        overrides:
          channel_limit: "100000"
  '';

  # The image's cron wrapper does `cd /config; . /config/cron` on CRON_SCHEDULE
  # and on start, so the script runs with cwd /config where config.yaml +
  # subscriptions.yaml live and a bare `ytdl-sub sub` finds them. The stock
  # /config/cron is a no-op warning; this replaces it.
  cronScript = pkgs.writeText "ytdl-sub-cron" ''
    ytdl-sub sub

    # By default ytdl-sub uses the channel avatar (a small round icon) as the show
    # poster, which looks bad. Always override it with the first season's poster
    # (a real video thumbnail) instead.
    for show in /tv_shows/*/; do
      first=$(ls "$show"season*-poster.jpg 2>/dev/null | sort | head -1)
      [ -n "$first" ] && cp "$first" "$show/poster.jpg"
    done
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
