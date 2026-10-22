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
