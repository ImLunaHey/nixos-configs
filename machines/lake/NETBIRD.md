# NetBird on Lake

Lake owns the NetBird control plane, embedded identity provider, dashboard, and
persistent database. The public DigitalOcean host is only an ingress gateway and
NetBird exit node.

## Public path

`netbird.flaked.org` resolves to DigitalOcean. A WireGuard tunnel independent of
NetBird connects DigitalOcean (`10.77.0.1`) to Lake. The gateway proxies to:

- Lake `10.0.0.46:8080/tcp`: dashboard
- Lake `10.0.0.46:8081/tcp`: management, signal, relay, API, and OAuth
- Lake `10.0.0.46:3478/udp`: STUN

The reverse proxy must send gRPC requests over h2c and retain long-lived gRPC and
WebSocket connections. The equivalent Caddy routes are:

```caddyfile
netbird.flaked.org {
  @grpc header Content-Type application/grpc*
  reverse_proxy @grpc h2c://10.0.0.46:8081

  @backend path /relay* /ws-proxy/* /api/* /oauth2/*
  reverse_proxy @backend 10.0.0.46:8081

  reverse_proxy /* 10.0.0.46:8080
}
```

Forward public UDP port 3478 through the WireGuard tunnel to Lake's UDP port
3478. The DigitalOcean forwarding rule must also masquerade this traffic as
`10.77.0.1` so replies return through the tunnel instead of Lake's normal
internet route. Do not carry this gateway tunnel over NetBird: peers need it to
reach the control plane before NetBird is connected.

## State and recovery

The `storage/netbird` ZFS dataset is mounted at `/mnt/storage/netbird`. It holds
the SQLite database, server state, and locally generated encryption keys. Back up
the complete dataset; the database cannot be recovered without its encryption
key.

After the public gateway and DNS are ready, open `https://netbird.flaked.org` to
create the initial account, then enrol Lake with:

```console
sudo netbird up
```

Keep Tailscale enabled until all peers, access policies, routes, DNS, and the
DigitalOcean exit node have been tested through NetBird.
## Pocket ID

Lake also hosts Pocket ID at `https://id.flaked.org`, pinned to v2.19.2.
Create a DNS record pointing to DigitalOcean and add this gateway route:

```caddyfile
id.flaked.org {
  reverse_proxy 10.0.0.46:1411
}
```

Carry this traffic over the same independent WireGuard link, with source
`10.77.0.1`. Pocket ID trusts forwarded client addresses only from that source.
Keep the backend port private: Docker-published ports need filtering in the
Docker forwarding path, not just the host INPUT firewall. Restrict gateway
routing to the intended ports. The gateway and tunnel configuration remain
external deployment prerequisites, as with NetBird above.

Choose the domain before enrolling passkeys: passkeys are tied to it. Restrict
public access at the gateway until the initial admin has been created at
`https://id.flaked.org/setup`, then register a passkey. Lake and clients must be
able to resolve and reach that HTTPS address without relying on NetBird.

### Connect NetBird

Use NetBird's [Pocket ID integration](https://docs.netbird.io/selfhosted/identity-providers/pocketid):

1. Create a confidential NetBird OIDC client in Pocket ID with PKCE disabled.
2. In NetBird's Settings → Identity Providers, add PocketID with issuer
   `https://id.flaked.org` (no trailing slash), using that client's ID and secret.
3. Copy the redirect URL displayed by NetBird into the Pocket ID client's
   callback URLs. Optionally set the logout callback to
   `https://netbird.flaked.org/oauth2/logout/callback`.
4. Assign a NetBird user group to the client and add the intended users.
5. Test Pocket ID login and peer enrolment before changing existing access.

Keep the client secret in the applications' configuration interfaces; do not
commit it or put it in dashboard environment variables. NetBird retains its
embedded identity service and local administrator for recovery.

### Pocket ID recovery

The `storage/pocket-id` dataset at `/mnt/storage/pocket-id` contains `data/`
(SQLite, uploads, and application state) and `encryption-key`. Initialization
generates the key locally once, outside the Nix store. It refuses to generate a
replacement if application data already exists. The container reads the key
from a read-only file mount. Back up and restore the **whole dataset together**;
losing the key makes encrypted signing keys and other sensitive data unusable.
No off-host backup schedule is added by this module.

Lake's health monitor checks the Pocket ID service alongside both NetBird
containers. After deployment, check the container health and public discovery:

```console
sudo docker inspect --format '{{.State.Health.Status}}' pocket-id
curl --fail https://id.flaked.org/.well-known/openid-configuration
```

See [Pocket ID installation](https://pocket-id.org/docs/setup/installation) and
[configuration](https://pocket-id.org/docs/configuration/environment-variables).
