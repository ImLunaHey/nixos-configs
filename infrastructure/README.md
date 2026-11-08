# Private service DNS

`netbird-dns.nix` declares Nova's NetBird address and private service records.
Nova's Caddy listeners use the same address and retain their Tailscale bindings.
HTTPS on `wt0` is admitted by the host firewall; NetBird policies decide which
peers can reach it. Jellyfin stays behind Caddy at `https://jellyfin.flaked.org`.

Evaluate and inspect the DNS plan on a machine with Nix:

```sh
nix-instantiate --eval --strict --json infrastructure/netbird-dns.nix > /tmp/netbird-dns.json
python3 scripts/sync-netbird-dns.py --manifest /tmp/netbird-dns.json --token-file /path/to/netbird-api-token
```

Add `--apply` after reviewing the plan. The token stays outside Git and the Nix
store. The script refuses to take over zones without the `nixos:` ownership
prefix, updates existing records idempotently, and reports stale zones for
explicit removal. It is an explicit administrative push, not a boot-time task
using a short-lived administrator token.

Each service has an exact-name DNS zone distributed to `personal-devices` and
`homelab`. This avoids overriding the rest of `flaked.org`, including mail,
NetBird management and Pocket ID. Clients must enable NetBird DNS management.
Server peers currently retain `--disable-dns` during migration; they do not use
these records until DNS is deliberately enabled on them.

Public Cloudflare records retain their existing NixOS sync to Tailscale while
old clients remain in use. Public whole-zone management through Terranix/OpenTofu
is still separate work; this manifest controls only the NetBird private answers.

For Apple TV, install the official NetBird TV app (tvOS 17+), select the
self-hosted server `https://netbird.flaked.org`, and sign in. Assign the enrolled
peer to the appropriate personal-device group before testing Jellyfin. Keep the
Jellyfin client's native authentication; a generic web SSO proxy in front of its
API can prevent TV clients from connecting.

# Pocket ID login for NetBird

NetBird uses Pocket ID (`https://id.flaked.org`) as an external OIDC provider
named **Pocket ID**. The confidential **NetBird** client in Pocket ID has PKCE
disabled as required by NetBird's embedded identity provider integration, with:

- Callback: `https://netbird.flaked.org/oauth2/callback`
- Logout callback: `https://netbird.flaked.org/oauth2/logout/callback`
- Allowed Pocket ID group: `netbird-users`

The client secret lives in the applications' state, outside Git and the Nix
store. Back up both applications' state and encryption keys. The short-lived
administrator API keys used to configure this integration are not login
credentials and are not needed for normal operation.

The local NetBird owner remains available for recovery. Pocket ID is a distinct
identity: its first login requires approval in the existing NetBird account.
The verified Pocket ID identity for Alexis Tyler is approved as an administrator;
its newly enrolled devices automatically join `personal-devices`. This group
can initiate connections to `homelab`, receives private service DNS, and is not
a destination of the GitHub deployment policy. Other Pocket ID users require
explicit membership and NetBird approval; granting them Pocket ID access does
not automatically make them NetBird administrators.

This OIDC integration authenticates NetBird. Individual applications use their
own OIDC clients, including Jellyfin below.

# Jellyfin upgrade and Pocket ID

Nova pins Jellyfin **12.4** by container digest in `machines/nova/jellyfin.nix`.
`packages/jellyfin-plugins` pins compatible plugin releases and builds four
small compatibility ports from upstream source: brrr.now, Cinema Mode,
SkinManager and ListenBrainz. The patches update .NET/Jellyfin dependencies;
source archives and all NuGet packages are hash-locked. ListenBrainz's settings
JavaScript is bundled from its TypeScript source during the Nix build.

The SSO plugin is the maintained Buco7854 fork, **5.0.0.3**, for Jellyfin 12.
The Pocket ID client uses:

- Name: `Jellyfin`, confidential, with PKCE enabled.
- Callback: `https://jellyfin.flaked.org/sso/OID/redirect/pocketid`
- Allowed group: `jellyfin-users`.
- Launch URL: `https://jellyfin.flaked.org/sso/OID/start/pocketid`.
- Jellyfin provider: `pocketid`, issuer `https://id.flaked.org`.
- Identity claim: `sub`, linked to the existing Jellyfin user, so changing a
  Pocket ID display name does not create a new Jellyfin account.
- Authorization/role synchronization disabled; existing Jellyfin permissions
  and password authentication remain available. Live TV flags match the
  existing user's policy.

The client secret is stored in Jellyfin's private plugin configuration, not in
Git or the Nix store. The configuration directory is restricted to the remapped
container user and root. Administrator API keys used for initial setup are not
needed for subsequent logins. Additional users must be allowed in Pocket ID;
link their existing Jellyfin accounts at `/SSOViews/linking` before using SSO
to preserve their library history. The login page offers **Sign in with Pocket
ID**. Native clients can retain password login or use Jellyfin Quick Connect
from an already signed-in browser; no authentication proxy intercepts the API.

## Backup and rollback

Jellyfin 12 rewrites the database. A system-generation rollback alone is not a
safe downgrade. `install-jellyfin-plugins.py` runs while the container is stopped
and saves `config` and `cache` before changing the pinned plugin bundle. It
preserves plugin configurations and archives superseded binaries. Backups live
in root-only `/var/backups/jellyfin/before-plugin-change-*/state.tar` directories.
Unchanged bundles do not create another backup. Plugin auto-updates are disabled
for the pinned plugins; update the Nix pins instead.

The initial stopped-server backup is
`/var/backups/jellyfin/pre-12.4-20261108/state.tar`, with a verified SHA-256 file,
the previous image digest, and the previous NixOS system path alongside it.
Before the live upgrade, the database migration was exercised on an isolated
copy using `--mode MigrateSystem`, with third-party binaries removed.

To roll back, stop `docker-jellyfin`, preserve the failed state in another
directory, restore **both** `config` and `cache` from the chosen pre-upgrade tar
with numeric ownership preserved, then activate the recorded old NixOS system.
That system must use the old Jellyfin image and must not run the new plugin
installer against restored data. The old image digest is
`jellyfin/jellyfin@sha256:333b647716631443a43c7fabac4b0c46b4e2f036bad19547e00958f10f721b85`.
Keep the backup until accounts, watched items, playback and client logins have
been verified. Run a full library scan after upgrading, as required by Jellyfin
12; the first scan can take longer than normal.

Deployment validation on 2026-11-08: Nova reports 12.4.0, all 11 third-party
plugins are active, all three user IDs and policies are unchanged, and an HTTPS
media range request through NetBird returned 206. The full library scan
completed successfully. A watched alternate edition of `Selfie` S01E01 was
consolidated into the episode's media sources, retaining its watched state.
Pocket ID accepted the pushed authorization request; completing login with the
user's passkey is the final browser check.

References: [Jellyfin 12 upgrade guidance](https://jellyfin.org/posts/jellyfin-release-12.0/)
and [maintained SSO plugin](https://github.com/Buco7854/jellyfin-plugin-sso).
