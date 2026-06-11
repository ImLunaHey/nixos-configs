# ytdl-sub subscriptions — add entries here, then commit & push (auto-deploys within ~15 min).
#
# Where each group lands (mapping lives in machines/nova/ytdl-sub.nix):
#   channels -> /mnt/media/youtube   one show per channel, episodes by upload date
#   shows    -> /mnt/media/youtube   a show built from playlists, one season per playlist
#   music    -> /mnt/media/music     audio only, artist / album / track
{
  # Whole YouTube channels (their uploads — not their playlists). A bare URL
  # self-names from the channel; or an attrset with optional fields:
  #   { url = "..."; name = "My Name"; description = true; limit = 25; }
  #     description = true  -> use each video's YouTube description as the plot
  #                           (default: no plot at all)
  #     limit = N           -> only grab the N most recent uploads (huge channels)
  channels = [
    { url = "https://www.youtube.com/@SortedFood"; description = true; limit = 25; }
  ];

  # Shows assembled from playlists. Give the show a name, then list its season
  # playlists in order — the first becomes Season 01, the second Season 02, etc.
  # A season can be a bare URL, or { name = "..."; url = "..."; } to title it.
  # A season URL can also be a *channel* — the collection preset dedups, so a
  # video in both the channel and a playlist downloads once (in the playlist).
  # Optional per-show fields:
  #   genre = "...";        Jellyfin genre (YouTube's category is unreliable)
  #   description = true;   use the videos' YouTube descriptions as plots
  #                         (default: no plot at all)
  shows = [
    {
      name = "Tip 2 Tip";
      genre = "Travel";
      seasons = [
        { name = "China"; url = "https://www.youtube.com/playlist?list=PLLGT0cEMIAze5tmNSlEvUKo-cQ0YrIs2j"; }
        { name = "Japan"; url = "https://www.youtube.com/playlist?list=PLLGT0cEMIAzeq_YFR_iHm831-GuOWlwUJ"; }
      ];
    }
  ];

  # Music — audio only. A bare URL names the artist from the uploader and the
  # album from the playlist; or { name = "Artist"; url = "https://..."; }.
  music = [
    # "https://www.youtube.com/@officialtheloniousmonk/releases"
  ];
}
