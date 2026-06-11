# ytdl-sub subscriptions — add entries here, then commit & push (auto-deploys within ~15 min).
#
# Where each group lands (mapping lives in machines/nova/ytdl-sub.nix):
#   channels -> /mnt/media/youtube   one show per channel, episodes by upload date
#   shows    -> /mnt/media/youtube   a show built from playlists, one season per playlist
#   music    -> /mnt/media/music     audio only, artist / album / track
{
  # Whole YouTube channels. A bare URL self-names from the channel; or use
  # { name = "My Name"; url = "https://..."; } to force the show name.
  channels = [
    # "https://www.youtube.com/@veritasium"
    # { name = "Kurzgesagt"; url = "https://www.youtube.com/@kurzgesagt"; }
  ];

  # Shows assembled from playlists. Give the show a name, then list its season
  # playlists in order — the first becomes Season 01, the second Season 02, etc.
  # A season can be a bare URL, or { name = "..."; url = "..."; } to title it.
  # Optional `genre = "...";` sets the Jellyfin genre (YouTube's own category is
  # unreliable — e.g. it reports "Gaming" for this travel series).
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
