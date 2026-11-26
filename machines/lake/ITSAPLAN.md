# Retired: It’s a Plan on Lake

It’s a Plan is no longer declared in the Lake configuration. Deploy Lake and
Nova through the normal deployment workflow to remove the container stack,
local router, backup timer, secret installation, and HTTPS virtual host.
The previous stack unit runs Compose `down` when stopped during the switch.
Verify that no containers with the Compose project label `itsaplan` remain.
Docker stays enabled for Lancache.

The `storage/itsaplan` ZFS dataset at `/mnt/storage/itsaplan`, including the
PostgreSQL database, attachments, SQL dumps, and existing snapshots, is retained.
No dataset or snapshot destruction is part of this removal. Scheduled Itsaplan
snapshots and pruning stop. The former Compose definition and encrypted
`secrets/itsaplan.env` remain recoverable from Git history; preserve the SOPS
recipient keys if recovery is needed, including access to `APP_ENCRYPTION_KEY`.

After deploying both hosts, explicitly remove the stale Cloudflare A record
and the owned NetBird DNS zone for `itsaplan.flaked.org`. The Cloudflare sync
only upserts records, and `scripts/sync-netbird-dns.py` reports stale owned
zones without deleting them. Remove the retired endpoint from MCP clients too.
These external changes are not performed by this configuration change.
