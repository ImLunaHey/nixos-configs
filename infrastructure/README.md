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

This OIDC integration authenticates NetBird. Individual applications need their
own OIDC clients if they are to use Pocket ID login; Jellyfin's native client
login is unchanged.
