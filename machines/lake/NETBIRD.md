# NetBird client on Lake

Lake's NetBird client uses `https://netbird.flaked.org` and runs alongside
Tailscale. The control plane, dashboard, relay/STUN, and Pocket ID live on the
Killdeer VPS. See [gateway deployment and onboarding](../gateway/README.md).

After deploying this client configuration and completing gateway onboarding:

```console
sudo netbird up
```

Keep Tailscale enabled until all peers, access policies, routes, DNS, and recovery
have been tested. The `wt0` interface is trusted by Lake's firewall, so configure
NetBird access policies before enrolling additional users. No independent
WireGuard gateway tunnel is needed, and no default internet exit route is set.
