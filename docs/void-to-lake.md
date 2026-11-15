# Move Void storage clients to Lake

The copied data is at `/mnt/storage/void` on Lake. This change serves that
directory directly; it does not merge it into Lake's existing libraries.

| Client | Local path | New source |
| --- | --- | --- |
| Nova | `/mnt/media` | `lake.localdomain:/mnt/storage/void/media` |
| Nova | `/mnt/games` | `lake.localdomain:/mnt/storage/void/games` |
| Nova | `/mnt/photos` | `lake.localdomain:/mnt/storage/void/photos` |
| Gilbert | `/mnt/rips` | `lake:/mnt/storage/void/rips` |
| Nova and Gilbert backups | `/mnt/backups` | `lake:/mnt/storage/void/backups` |
| Pulsar | Finder SMB mount | `smb://luna@lake/void-media` |

Lake also exposes authenticated SMB shares `void-files`, `void-games`,
`void-photos`, `void-backups` and `void-rips`. Update manual SMB bookmarks to
these shares. On macOS the imported media volume is now named `void-media`;
update any local tools referring to `/Volumes/media` to the new mounted path.
Lake's existing `media`, `files`, `photos`, `backups`, `games`, `rips`, `scans`
and Time Machine shares retain their original paths. Nova's existing movies
and shows mounts retain their original Lake exports.

## Cutover order

Merging this PR is not the cutover. Use the same committed revision for all
deployments with `scripts/deploy.py`; build beforehand where practical.

1. Pause scheduled backups and all writers to Void: Immich uploads, ytdl-sub,
   Gilbert's ripping jobs, and SMB uploads. Stop the affected containers and
   timers; readers with open NFS files must also stop before unmounting.
   Disconnect Pulsar and other SMB clients. Keep Void online for rsync.
2. Stop Void's Samba and NFS serving after clients are quiesced, preventing
   new network writes. Leave SSH and the storage datasets available. Do not
   allow clients to write to Lake's imported shares yet.
3. Run the final rsync from Void's `/mnt/storage/` to Lake's
   `/mnt/storage/void/`, preserving owners, ACLs, xattrs, hard links and times
   (`-aHAX --numeric-ids`). Review deletions separately: the initial copy did
   not delete destination files. Never sync this source over `/mnt/storage/`.
4. Verify the final copy while writes remain paused. A read-only
   `rsync -aHAXnci --numeric-ids` must report no file differences. To audit
   destination-only paths, add `--delete` **only to this dry run**, and review
   those paths before deciding whether to remove anything. Check exit status
   as well as itemized output; exit 0 alone does not mean identical trees.
5. Deploy Lake first. Check `lake-imported-storage.service`, `exportfs -v`
   and Samba's configuration. The preparation service deliberately fails if
   the pool or imported directories are missing, rather than serving empty
   directories. Confirm NFSv4 TCP port 2049 is reachable by the clients.
6. With applications and backup timers still stopped, unmount the old NFS
   mounts and stop their automount units on Nova and Gilbert. Deploy their
   new configurations, trigger the new mounts and inspect `findmnt` to confirm
   every source is Lake. A rebuild alone is not proof that an existing busy
   NFS mount has switched servers. Check UID 100000 can write the imported
   photos, music and YouTube directories, and that backup repositories open.
7. Deploy Pulsar, eject any remaining Void volume, and connect to
   `smb://luna@lake/void-media`. Lake may need its own saved Keychain login.
   Update other manually configured clients. Resume applications and backup
   timers only after their new mounts are confirmed.
8. Check Immich uploads, media playback, ROMM, ripping destinations and backups.
   Once clients use Lake and the final copy is verified, power down Void.
   Check the selected drive's SMART health and capacity before replacing
   Lake's faulted drive. Keep the other Void drives intact during the rebuild.

Do not rsync Void over the destination after Lake accepts new writes: it can
overwrite newer files or restore stale backup metadata. If rollback is needed
after writes resume, stop writers and reconcile both sides first.

Void's host configuration, deploy target and VPN identity remain available
until shutdown is confirmed. Removing them is a separate retirement step.
