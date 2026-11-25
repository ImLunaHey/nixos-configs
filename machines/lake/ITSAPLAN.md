# It's a Plan on Lake

After deployment, Community v1.13.0 is available privately at
**https://lake.tail3275e2.ts.net:4201** over Tailscale. The first registered account
becomes admin: register Luna first, then set registration to invite-only or closed
in God mode. Access follows existing tailnet ACLs.

## Operations

Deploy through the repository's usual Lake deployment process after merging.
Check `systemctl status itsaplan itsaplan-router itsaplan-proxy` and
`journalctl -u itsaplan -b`. Restart with `systemctl restart itsaplan`.

Caddy routes `/api/*` with the prefix stripped and forwards MCP OAuth discovery.
Tailscale provides HTTPS on port 4201. The other ports (4200, 4202, 4203) bind only
to loopback. Board and Lancache keep their existing ports.

The separate PostgreSQL 17 container, attachments, and pre-migration SQL dumps
use `/mnt/storage/itsaplan`, on the `storage/itsaplan` ZFS dataset. Migrations
must succeed before the application services start.

Edit credentials with `sops secrets/itsaplan.env`. The file is encrypted to Luna
and Lake and decrypted root-only to `/run/secrets/itsaplan_env`. Preserve
`APP_ENCRYPTION_KEY`: changing it prevents decrypting saved integration credentials.
Telemetry is disabled. Configure email and integrations in God mode. Incoming
GitHub webhooks need a separate public webhook route and `GIT_WEBHOOK_BASE_URL`;
they cannot reach this private endpoint.

## Recovery

Around 04:00 daily, the backup service briefly stops the stack, snapshots the
whole dataset, and starts it again. This causes a short outage but keeps database
and attachments consistent. Snapshots are retained for 14 days. Run manually with
`systemctl start itsaplan-backup`. Pre-migration SQL dumps have upstream's 30-day
retention. Snapshots are local recovery points, not protection against pool loss;
off-host replication is not configured here.

To recover, stop the backup timer and stack. Inspect snapshots with
`zfs list -t snapshot -r storage/itsaplan`; preferably clone one for inspection
before replacing live data. Restore database and attachments together and use
the matching image version, then restart the stack and timer. Preserve the
encrypted environment file and its decryption keys with recovery material.

## Updates and Pro

Review upstream release notes and Compose changes, take a snapshot, update all
application image versions (including `migrate`), and deploy. Do not downgrade
images against a migrated database without restoring a matching recovery point.

Compose is adapted from
https://github.com/croffasia/itsaplan/blob/v1.13.0/docker-compose.yml (AGPL-3.0).
For Pro, use the image names/configuration from the matching upstream
`docker-compose.pro.yml`, preserving our project name, volumes, environment and
proxy routing. Enter the license in God mode → License. The data and self-hosting
remain the same; this Community deployment needs no paid license.
