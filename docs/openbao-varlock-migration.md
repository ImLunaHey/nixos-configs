# OpenBao and Varlock migration

This change deliberately runs OpenBao and Varlock alongside SOPS first. Do not
remove SOPS or change a service consumer until that host can resolve its complete
Varlock schema and has survived a reboot.

## Security model

- OpenBao initially listens with TLS only on Lake's loopback address. This
  prevents another LAN client from claiming an uninitialized vault. The later
  consumer cutover changes it to `10.0.0.46:8200` and opens the LAN firewall
  only after initialization and migration are complete.
- OpenBao's integrated Raft database lives in `/var/lib/openbao` on Lake's NVMe
  root filesystem. It does not depend on the bulk ZFS pool being healthy.
- The private CA and initial recovery material live below
  `/var/lib/openbao-bootstrap`, mode `0700`/`0600`.
- The static auto-unseal key is a SHA-256 derivation of Lake's SSH host private
  key, passed into the sandboxed service with a systemd credential. Neither key
  is copied into the Nix store.
- Every host gets a separate AppRole that can read only
  `secret/data/hosts/<host>`. AppRole tokens are renewable hourly service tokens.
- Existing encrypted SOPS data stays in Git until the later consumer cutover is
  complete and rollback has been tested.

Lake's `/etc/ssh/ssh_host_ed25519_key` is therefore critical recovery material.
Losing or replacing it makes the OpenBao database impossible to unseal. Keep an
offline backup of that key, the OpenBao recovery keys, the CA key, and the Raft
data. Never commit any of them.

## Stage 1: deploy and initialize

After deploying the Lake configuration:

```bash
sudo systemctl status openbao
sudo openbao-init
```

Immediately make an offline encrypted backup of:

- `/etc/ssh/ssh_host_ed25519_key`
- `/var/lib/openbao-bootstrap/init.json`
- `/var/lib/openbao-bootstrap/tls/ca.key`
- `/var/lib/openbao`

The public CA certificate is
`/var/lib/openbao-bootstrap/tls/ca.crt`. It is safe to distribute, but the CA
private key is not.

## Stage 2: copy SOPS values and create host identities

Run the migration from a clean checkout of this repository on Lake:

```bash
sudo ./scripts/openbao-migrate-sops.sh
```

The script decrypts one value at a time directly into OpenBao, without printing
it or writing a plaintext export. It creates root-only AppRole files under
`/var/lib/openbao-bootstrap/approles`. Re-running it updates secret values but
does not replace an AppRole credential file that already exists.

Copy each host's matching `.env` file and the public `ca.crt` over an
authenticated channel. Store them as root-only files outside the repository.
Delete an AppRole file from Lake after confirming its destination and offline
backup.

## Stage 3: verify Varlock locally

Install the pinned plugin and verify Lake's schema against the loopback listener:

```bash
varlock install-plugin @varlock/hashicorp-vault-plugin@2.1.2
set -a
. /var/lib/openbao-bootstrap/approles/lake.env
set +a
export NODE_EXTRA_CA_CERTS=/var/lib/openbao-bootstrap/tls/ca.crt
export BAO_ADDR=https://127.0.0.1:8200
varlock load --agent --path ./varlock/hosts/lake
```

`--agent` verifies resolution while redacting sensitive output. The schemas in
`varlock/hosts` cover every currently declared SOPS key for each NixOS host.

## Stage 4: consumer cutover

Make the consumer changes in a follow-up PR, one host at a time. That change must
bind OpenBao to `10.0.0.46`, open TCP 8200 only on the intended LAN or mesh
interface, distribute the public CA, and add `openbao.home.arpa` resolution to
each client. Each service should use `varlock run --inject vars` or a root-only
rendered credential file; never put a resolved value into the Nix store or a
command line. Keep SOPS as the rollback path until all four hosts have rebooted
successfully, then remove `sops-nix`, `.sops.yaml`, the encrypted YAML, and the
old bootstrap path.
