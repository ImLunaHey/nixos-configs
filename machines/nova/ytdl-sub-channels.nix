# ytdl-sub subscriptions — add entries here, then commit & push (auto-deploys within ~15 min).
#
# The simplest entry is just a URL on its own line:
#     "https://www.youtube.com/@veritasium"
# ytdl-sub names the show/artist from the source itself (channel name / playlist title).
#
# To force a name instead of using the source's own, write:
#     { name = "My Name"; url = "https://..."; }
#
# Where each group lands (mapping lives in machines/nova/ytdl-sub.nix):
#   channels  -> /mnt/media/youtube   one TV show per channel, episodes by upload date
#   playlists -> /mnt/media/youtube   each playlist as its own ordered season
#   music     -> /mnt/media/music     audio only, artist / album / track
{
  # Whole YouTube channels, organised by upload date. Named from the channel.
  channels = [
    # "https://www.youtube.com/@veritasium"
    # { name = "Kurzgesagt"; url = "https://www.youtube.com/@kurzgesagt"; }
  ];

  # Playlists — each downloaded as its own season. Named from the playlist title.
  playlists = [
    "https://www.youtube.com/playlist?list=PLLGT0cEMIAze5tmNSlEvUKo-cQ0YrIs2j"
  ];

  # Music — audio only. Artist named from the uploader, album from the playlist title.
  music = [
    # "https://www.youtube.com/@officialtheloniousmonk/releases"
  ];
}
