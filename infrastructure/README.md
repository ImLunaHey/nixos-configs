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

Each service has an exact-name DNS zone distributed to `personal-devices`,
`homelab` and `nixos:administrators`. This avoids overriding the rest of `flaked.org`, including mail,
NetBird management and Pocket ID. Clients must enable NetBird DNS management.
Server peers currently retain `--disable-dns` during migration; they do not use
these records until DNS is deliberately enabled on them.

Public Cloudflare records are synchronized from Nix. Jellyfin overrides the
default Tailscale destination with Gateway’s public address, `23.150.68.231`.
NetBird clients still resolve Jellyfin directly to Nova. Public whole-zone management through Terranix/OpenTofu
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
can initiate HTTPS connections to Nova, receives private service DNS, and is not
a destination of the GitHub deployment policy. Administrative access is assigned
to explicitly reviewed peers, never inherited from this login. Other Pocket ID users require
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
  remain authoritative. New viewers receive explicit library permissions.

The client secret is stored in Jellyfin's private plugin configuration, not in
Git or the Nix store. The configuration directory is restricted to the remapped
container user and root. Administrator API keys used for initial setup are not
needed for subsequent logins. Additional users must be allowed in Pocket ID;
link their existing Jellyfin accounts at `/SSOViews/linking` before using SSO
to preserve their library history. The login page offers **Sign in with Pocket
ID** on a forest-themed page, with its Unsplash image served locally. Password
authentication and password recovery endpoints return 403 at both Caddy
listeners; hiding the forms is only presentation. Existing sessions continue
to work. Native clients use Jellyfin Quick Connect authorized from a Pocket ID
session; no generic authentication proxy intercepts their API requests.

The public route is Gateway HTTPS → Nova’s NetBird-only TCP 9443 listener, with
upstream certificate verification for `jellyfin.flaked.org`. NetBird permits
only that backend port from Gateway. Private devices use Nova TCP 443 directly.
The backend remains bound to host loopback. Caddy trusts forwarded addresses
only from Gateway, and Jellyfin trusts loopback plus the exact Docker bridge
gateway. Local administrator recovery remains possible over SSH.

The family accounts are linked by stable Pocket ID subjects. Hannah has only
Movies and Shows, no administrator, deletion, download, Live TV or other-user
control rights. Rachel retains her existing account and library history. Both
belong only to `jellyfin-users`, which grants no NetBird access. Passkey
onboarding uses private, expiring one-time links; credentials are never stored
in this repository.

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
Pocket ID accepted the pushed authorization request. The user confirmed that a
private-window passkey login opens the existing `luna` account and library over
NetBird.

References: [Jellyfin 12 upgrade guidance](https://jellyfin.org/posts/jellyfin-release-12.0/)
and [maintained SSO plugin](https://github.com/Buco7854/jellyfin-plugin-sso).


# NetBird client updates

Gateway, Lake, Nova and Void share the **0.82.0** client pin in
`machines/gateway/netbird-client-package.nix`. It installs the checksum-verified
upstream Linux amd64 binary and checks its version during the Nix build. The
package lives inside Gateway's standalone flake so its deployment archive is
self-contained. The GitHub deployment workflow pins the same archive and hash;
update both pins together when upgrading clients.

Deploy through `scripts/deploy.py`, one host at a time, using the existing
Tailscale hostnames for home servers and Gateway's public SSH address. Restarting
the client briefly interrupts its tunnel. Verify the daemon version, connection,
existing peer ID/address, and permitted and denied traffic after activation.
Client upgrades preserve stored registrations and do not require setup keys.
They do not change the separately pinned management server or dashboard.

The MacBook and iOS/tvOS apps are maintained outside these NixOS configurations.
The MacBook already reports 0.82.0. Mobile apps can report a CI build identifier
instead of the desktop/Linux version; use their App Store update status rather
than comparing that identifier numerically.

Validated on 2026-11-08: all four Linux daemons report 0.82.0 and retain their
peer IDs and IPv4 addresses. Administrative SSH and Jellyfin HTTPS work. An
isolated 0.82.0 client passes both the personal-device and deployment policy
tests after group changes propagate; Gateway remains unable to initiate home
server connections. The policy plan still reports zero changes. Temporary test
peers and credentials were removed after validation.

# NetBird access policies

`netbird-access.nix` declares the static peer identities, groups and policies.
Rules apply to the NetBird tunnel; host firewalls, LAN access and retained
Tailscale access remain separate controls.

| Source | Destination | Allowed traffic |
| --- | --- | --- |
| Explicit administrators (currently the MacBook) | Gateway, Lake, Nova, Void | Initiate TCP/UDP; bidirectional ICMP for diagnostics |
| Personal devices, including future Pocket ID enrolments | Nova | Initiate TCP 443 only |
| GitHub deployment runners | Gateway, Lake, Nova, Void | Initiate TCP 22 only |
| Lake, Nova, Void | Each other | All protocols, subject to host firewalls |
| Gateway | Nova | Initiate TCP 9443 only (public Jellyfin backend) |

Gateway proxies its local NetBird and Pocket ID services plus Jellyfin through
a dedicated Nova listener. Its `nixos:jellyfin-ingress` policy grants TCP 9443
only; Gateway remains outside the home-server mesh and cannot initiate SSH or
reach Nova’s other HTTPS sites.

Nova's HTTPS sites share one address and port. The personal-device rule permits
all of those HTTPS sites, not only Jellyfin; each application still authenticates
its users. Hostname-specific restrictions would require separate ingress or
application-level rules. No subnet route or exit node is introduced.

Administrative groups use exact peer IDs and expected addresses, not device
names. Signing into a TV with the administrator's Pocket ID account grants only
`personal-devices`, not the MacBook's administrative network access. The sync
refuses automatic assignment of managed static groups through users or setup
keys. It preserves dynamic peer membership in the enrolment groups.

## Apply changes

Evaluate on a machine with Nix, then review the plan:

```sh
nix-instantiate --eval --strict --json infrastructure/netbird-access.nix > /tmp/netbird-access.json
python3 scripts/sync-netbird-access.py --manifest /tmp/netbird-access.json --token-file /path/to/token --phase enforce
```

Use a private administrator token file. The token is never stored in the
manifest, snapshot or Nix store. Applying remains an explicit administrative
push, rather than giving deployment runners a permanent network-admin token.

Stage replacement rules while keeping legacy grants available:

```sh
python3 scripts/sync-netbird-access.py --manifest /tmp/netbird-access.json --token-file /path/to/token --phase prepare --apply --snapshot /private/before-prepare.json
```

Check that the approved administrator can still reach every deployment target.
Then enforce the restrictions:

```sh
python3 scripts/sync-netbird-access.py --manifest /tmp/netbird-access.json --token-file /path/to/token --phase enforce --apply --snapshot /private/before-enforce.json
```

`enforce` reads the replacement policies back before disabling explicitly
identified legacy rules. Unmanaged enabled policies, identity/address drift,
duplicate names, ephemeral static peers, and unexpected automatic group grants
stop the sync. Stale owned policies are not silently deleted: remove them through
an explicitly reviewed migration. This NetBird version supports one rule per
policy, so TCP, UDP and ICMP administration are separate policies.

After creating the groups, apply `netbird-dns.nix` using the DNS command above.
Test permitted **and denied** connections. A repeat access apply should report
zero changes. Unit tests run with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_netbird_access.py
```

For rollback, restore the snapshot taken immediately before enforcement:

```sh
python3 scripts/sync-netbird-access.py --token-file /path/to/token --restore /private/before-enforce.json --apply
```

Restoration reinstates saved access before removing newly created policies and
static groups. It does not overwrite dynamic enrolment groups or identities.
The 2026-11-08 pre-enforcement snapshot is retained on Gateway at
`/var/backups/netbird-policies/before-enforce-20261108.json`.

## Permanent server enrolment

The initial homelab key and its four server registrations were ephemeral. On
2026-11-08, each server was re-enrolled using a limited-use, non-ephemeral key;
its original NetBird IP and SSH host identity were retained. The manifest holds
the new peer IDs. The old homelab key and the completed migration key were
revoked. Existing servers reconnect using their stored identities and do not
need a setup key on every boot. GitHub runners remain deliberately ephemeral.

For future servers, create a **non-ephemeral** setup key and explicitly review
its peer ID, address and group membership in the manifest. The `homelab`
enrolment group alone grants neither administrative nor deployment access.
Backups of the previous local client state are in
`/var/backups/netbird-before-permanent` on each server. Restoring those files
alone will not recreate the retired server-side peer registrations.

## Verified behavior

After enforcement on 2026-11-08, real SSH connections from the MacBook reached
all four servers, and Jellyfin HTTPS still returned 200. An isolated personal
peer could reach Nova TCP 443 but could not reach SSH on any server. Reassigning
that test peer solely to `github-deploy` permitted TCP 22 on all four servers
and denied Nova TCP 443. Gateway could not initiate SSH to Lake/Nova/Void or
HTTPS to Nova on TCP 443. The later public Jellyfin route deliberately adds only
Nova TCP 9443; recheck both allowed and denied ports after applying it. All permanent servers report non-ephemeral registrations at
their original IP addresses. Temporary test credentials and peers were removed.
