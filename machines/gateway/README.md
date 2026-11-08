# Killdeer gateway

Provisioned as `gateway` in the `ImLunaHey` Killdeer account:

- IPv4: `23.150.68.231`
- Micro: 1 vCPU, 1 GB RAM, 10 GB disk (approximately $6/month with IPv4)
- Provider image: NixOS 25.11; managed configuration tracks NixOS 26.05
- SSH: `ssh luna@23.150.68.231`

This directory is a standalone flake so rebuilding this public host does not
require access to Lake's private Git inputs or secrets. `admin.pub` is the
administrator's public SSH key. The provider's cloud-init networking, QEMU guest
agent, boot configuration, and `plover` recovery account are retained.

Deploy this directory to `/etc/nixos`, then run:

```console
sudo nixos-rebuild build --flake /etc/nixos#gateway
sudo nixos-rebuild switch --flake /etc/nixos#gateway
```

To update the pinned NixOS packages, run `sudo nix flake update --flake /etc/nixos`
and rebuild. Copy the resulting `flake.lock` back into this directory and commit
it. OS updates are manual until a deployment/update workflow is configured.

The initial configuration provides key-only SSH, a firewall, swap, and bounded
journal storage. Only SSH is exposed. It does not yet deploy the public Caddy
routes, WireGuard link to Lake, NetBird exit node, or DNS records. See
[the service plan](../lake/NETBIRD.md) for those next steps. Existing Tailscale
services elsewhere are unchanged.

Manage the VM with `ssh ImLunaHey@killdeer.digital status gateway` or attach to its
serial console with `ssh -t ImLunaHey@killdeer.digital console gateway`.
