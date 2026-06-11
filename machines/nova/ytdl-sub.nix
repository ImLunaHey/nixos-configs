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
  #   { url; name?; genre?; description?; limit?; }
  #     name        -> override the derived name (channel/artist)
  #     genre       -> Jellyfin genre (YouTube's per-video category is unreliable)
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
      ++ lib.optional (e ? genre) "    tv_show_genre: \"${e.genre}\""
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
        # Skip Shorts (their URL contains /shorts/)
        match_filters:
          filters:
            - "original_url!*=/shorts/"
        overrides:
          channel_limit: "100000"
  '';

  # Post-download step: strip creator promo/ad boilerplate from each episode's
  # Jellyfin <plot>, editing the .nfo in place (fixes already-downloaded files
  # too, no re-download). Boilerplate is auto-detected per show as lines that
  # repeat across many of that channel's episodes (real descriptions are unique;
  # ads are copy-pasted) — the plot is truncated at the first such line, which
  # also drops the per-video tracking URLs that follow. `adMarkers` from
  # ytdl-sub-channels.nix are extra manual cut-points for one-offs.
  adMarkersPy = "[" + lib.concatMapStringsSep ", " (m: "\"${m}\"") (subs.adMarkers or []) + "]";
  cleanDescScript = pkgs.writeText "ytdl-sub-clean-descriptions.py" ''
    import glob, json, os, re
    from collections import Counter
    from xml.sax.saxutils import escape

    markers = ${adMarkersPy}

    for show in sorted(glob.glob("/tv_shows/*/")):
        eps = []
        for ij in glob.glob(show + "**/*.info.json", recursive=True):
            nfo = ij[:-len(".info.json")] + ".nfo"
            if not os.path.exists(nfo):
                continue
            try:
                desc = json.load(open(ij, encoding="utf-8")).get("description") or ""
            except Exception:
                continue
            eps.append((nfo, desc))
        n = len(eps)
        boiler = set()
        if n >= 4:
            freq = Counter()
            for _, d in eps:
                for line in set(x.strip() for x in d.split("\n") if len(x.strip()) >= 12):
                    freq[line] += 1
            thr = max(3, round(n * 0.3))
            boiler = {l for l, c in freq.items() if c >= thr}
        for nfo, desc in eps:
            lines = desc.split("\n")
            cut = len(lines)
            for i, l in enumerate(lines):
                if l.strip() in boiler:
                    cut = i
                    break
            cleaned = "\n".join(lines[:cut])
            marker_cut = False
            for mk in markers:
                j = cleaned.find(mk)
                if j != -1:
                    cleaned = cleaned[:j]
                    marker_cut = True
            if cut == len(lines) and not marker_cut:
                continue
            cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
            try:
                s = open(nfo, encoding="utf-8").read()
            except Exception:
                continue
            m = re.search(r"<plot>(.*?)</plot>", s, re.S)
            if not m:
                continue
            new = s[:m.start(1)] + escape(cleaned) + s[m.end(1):]
            if new != s:
                open(nfo, "w", encoding="utf-8").write(new)
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

    # Strip channel ad/promo boilerplate from episode descriptions.
    python3 /config/clean-descriptions.py
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
      "${cleanDescScript}:/config/clean-descriptions.py:ro"
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
