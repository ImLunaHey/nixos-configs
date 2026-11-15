# Move storage from Void to Lake

Clients keep the same directory and SMB share names. Only the server changes.

| Client | Local path | New source |
| --- | --- | --- |
| Nova | `/mnt/media` | `lake.localdomain:/mnt/storage/media` |
| Nova | `/mnt/games` | `lake.localdomain:/mnt/storage/games` |
| Nova | `/mnt/photos` | `lake.localdomain:/mnt/storage/photos` |
| Gilbert | `/mnt/rips` | `lake:/mnt/storage/rips` |
| Nova and Gilbert backups | `/mnt/backups` | `lake:/mnt/storage/backups` |
| Pulsar | Finder SMB mount | `smb://luna@lake/media` |

Use Lake's existing `media`, `files`, `photos`, `backups`, `games` and `rips`
SMB shares. Nova's movies and shows mounts already point at Lake and stay as
configured. Lake's scans, Time Machine and other existing data remain in place.

## Prepare the data

The initial copy has been moved from the temporary `/mnt/storage/void`
directory into the six canonical directories on Lake. Existing Lake data was
preserved; the only duplicate files were two byte-identical macOS metadata
files. The empty staging directory has been removed.

Compare overlapping paths before copying. Keep Lake's existing movies, shows,
backup repositories and other files; resolve differing files at the same path
explicitly. Do not blindly overwrite them, use `--delete`, or replace the
whole `/mnt/storage` tree. The configuration does not move or delete data automatically.

## Cutover order

1. Build the configurations before the maintenance window. Use the same
   committed revision with `scripts/deploy.py` for each deployment.
2. Pause writers on both hosts' affected shares: Immich uploads, ytdl-sub,
   ripping jobs, backup jobs/timers and SMB uploads. Stop readers with open NFS
   files as well, and disconnect SMB clients. Stop Void's NFS and Samba serving
   after clients are quiesced, retaining SSH and mounted storage for rsync.
3. Final-sync
   each of Void's six source directories directly to Lake's matching
   `/mnt/storage/<name>/` directory with `rsync -aHAX --numeric-ids`. Review a
   dry run first, especially overlapping paths; do not delete Lake-only files.
   Do not write further changes into the staging directory.
4. Verify each source directory against its canonical destination with a
   read-only `rsync -aHAXnci --numeric-ids`. Review itemized differences and exit
   status. Lake-only data is expected; zero exit status alone does not prove
   equality. Resolve conflicts explicitly before proceeding.
5. Deploy Lake first. Check `exportfs -v`, Samba's configuration and TCP port
   2049 connectivity. Confirm the six canonical directories contain the data.
6. Keep applications and timers stopped. Unmount old NFS mounts and stop their
   automount units on Nova/Gilbert, deploy their new configurations, trigger
   the mounts and confirm their Lake sources with `findmnt`. A rebuild alone
   does not prove that a busy NFS mount changed servers. Confirm UID 100000 can
   write photos, music and YouTube, and that the backup repositories open.
7. Deploy Pulsar, eject the old Void SMB volume, and mount
   `smb://luna@lake/media`. Save Lake's login in Keychain if needed. Update
   manual SMB bookmarks to Lake using the existing share names.
8. Resume writers and test uploads, playback, ROMM, ripping and backups. Once
   clients use Lake and verification is complete, power down Void. Check the
   replacement drive's SMART health and exact capacity before reusing it, and
   keep the remaining Void drives intact during Lake's rebuild.

Do not sync Void over Lake after writes resume on Lake. A rollback at that
point requires stopping writers and reconciling both sides. The initial staging copy has already been consolidated into the canonical paths. Void's host config, deploy target and VPN identity
remain available until retirement is confirmed.
