# NetBird and Pocket ID on Killdeer

The `gateway` VPS in the `ImLunaHey` Killdeer account hosts Caddy, the NetBird
combined management/signal/relay/STUN server, its dashboard, and Pocket ID.
Lake runs only a NetBird client alongside its existing Tailscale client.

- Public IPv4: `23.150.68.231`
- Basic: 1 vCPU, 2 GB RAM, 25 GB disk (approximately US$12/month with IPv4)
- NixOS 26.05, pinned by this directory's standalone flake
- SSH: `ssh luna@23.150.68.231`
- DNS-only A records: `netbird.flaked.org` and `id.flaked.org` → `23.150.68.231`

This independent flake avoids any dependency on Lake's private Git inputs or
secrets. The provider's cloud-init networking, boot configuration, QEMU guest
agent, and `plover` recovery account are retained. There is no separate WireGuard
tunnel and no internet exit route is enabled by this configuration.

## Deployment

Copy this directory's Nix files, `admin.pub`, and `flake.lock` to `/etc/nixos`:

```console
sudo nixos-rebuild build --flake /etc/nixos#gateway
sudo nixos-rebuild switch --flake /etc/nixos#gateway
```

Update packages with `sudo nix flake update --flake /etc/nixos`, rebuild, and
commit the resulting lock file here. OS and container updates are explicit;
container images are pinned by version and digest.

## Network and first login

Caddy handles TLS on TCP 80/443. It proxies the dashboard on loopback 8080,
management/signal/relay/OAuth via port 8081, and Pocket ID on loopback 1411.
The pinned combined server binds port 8081 on all interfaces even if a host is
specified in its listen address; the firewall blocks external access to it.
NetBird uses host networking so STUN on UDP 3478 sees each peer's real source
address. Only SSH, HTTP/HTTPS, and STUN are admitted by the public firewall;
backend HTTP, health, and metrics ports are not opened.

The first boot creates `/var/lib/gateway-bootstrap/access.caddy`, which denies
external access to both sites until the operator adds their public IP to its
`remote_ip` matcher. Allow loopback and the VPS's own public IP as well, so local
OIDC discovery works. The deployed file initially allows the provisioning
connection. Edit it via SSH if your public IP changes, then reload Caddy:

```console
sudo systemctl reload caddy
```

1. Visit `https://netbird.flaked.org` and claim the initial NetBird administrator.
2. Visit `https://id.flaked.org/setup`, create the Pocket ID administrator, and
   register a passkey. Passkeys are bound to this domain.
3. Follow [NetBird's Pocket ID integration](https://docs.netbird.io/selfhosted/identity-providers/pocketid):
   create a confidential OIDC client in Pocket ID with PKCE disabled; add it in
   NetBird Settings → Identity Providers with issuer `https://id.flaked.org`.
   Copy NetBird's displayed callback URL into the Pocket ID client, and assign
   the intended users through a client access group. Keep the client secret in
   these application interfaces, never in Git or dashboard environment variables.
4. Verify Pocket ID login. Retain the local NetBird admin for recovery.
5. Once both administrators are claimed, remove the temporary restriction:

```console
sudo truncate -s 0 /var/lib/gateway-bootstrap/access.caddy
sudo systemctl reload caddy
```

6. Enrol Lake with `sudo netbird up` after deploying its client configuration.
   Keep Tailscale until peers, policies, routes, DNS, and recovery are tested.

With the setup restriction active, peers outside the allowed IPs cannot use the
control plane. The VPS is in Minneapolis: dashboard/sign-in and relayed traffic
cross the Atlantic for UK users; working direct UK peer connections do not.

## State and recovery

- `/var/lib/netbird-control-plane`: SQLite database, server state, configuration,
  and encryption/authentication secrets
- `/var/lib/pocket-id`: SQLite/uploads under `data/` and `encryption-key`
- `/var/lib/caddy`: certificates and ACME account
- `/var/lib/gateway-bootstrap`: initial access restriction

Keys are generated locally outside the Nix store and retained across rebuilds.
Initialization refuses to regenerate missing keys when database state exists.
Back up the complete state directories, including keys, together. For a simple
consistent snapshot, stop the three application containers, copy their state,
then restart them. Provider storage replication is not an off-host backup; an
off-host backup schedule still needs configuring.

Check `systemctl --failed`, `docker ps`, and the three `docker-*.service` journals.
Verify Pocket ID with `sudo docker exec pocket-id /app/pocket-id healthcheck`,
and check OIDC discovery at both public issuers. Test STUN from outside the VPS,
and test client enrolment and a relayed connection before retiring Tailscale.

Manage the VM with `ssh ImLunaHey@killdeer.digital status gateway`; serial console:
`ssh -t ImLunaHey@killdeer.digital console gateway`.

The combined server's legacy relay health endpoint on port 9000 reports 503
with `listeners: null` in v0.81.3 because the relay is multiplexed onto the
management listener. Do not use that endpoint as a restart trigger; validate
OIDC discovery, the relay WebSocket endpoint, and STUN instead.
