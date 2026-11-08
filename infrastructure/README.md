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
