# Tower

`nixosConfigurations.tower` is the headless x86_64 gaming-PC configuration.
It provides DHCP, key-only SSH for `luna`, passwordless sudo, Tailscale, Codex, T3 Code, and local GPU inference. The administrative public key is the same
checked-in key used by Gateway. Confirm that the installing client has its
corresponding private key before rebooting.

Tower imports `profiles/base.nix` directly: initial boot does not need SOPS,
OAuth credentials, NAS mounts, or existing homelab services. Automatic upgrades
are disabled. There is no desktop environment.

## Installation from the minimal ISO

Hardware detected during installation on 2026-11-22:

- AMD Ryzen 7 9700X, 8 cores / 16 threads; 32 GB installed RAM.
- NVIDIA GeForce RTX 5070 Ti, 16 GB VRAM; open NVIDIA kernel modules enabled.
- Realtek RTL8125 2.5 GbE, interface `enp7s0`; DHCP (installer: `10.0.0.161`).
- Kingston SNV3S1000G 1 TB, serial `50026B73846BED1F`.
- UEFI boot, 1 GiB FAT32 EFI partition mounted at `/boot`, remaining disk ext4
  mounted at `/`; zram swap. The previous `Games` partition was erased with
  explicit confirmation. Filesystem UUIDs are in `hardware-configuration.nix`.

For a future reinstall, regenerate the hardware configuration after formatting.

1. Boot the minimal ISO in UEFI mode and establish networking and SSH access.
2. Inspect CPU, RAM, GPU/VRAM, network interfaces, and disks again before erasing.
3. Confirm the SSD to erase by model, capacity, and serial. Partition only that
   disk and mount its root filesystem at `/mnt` and EFI system partition at
   `/mnt/boot`. No disk-erasure commands or device paths are preconfigured here.
4. Run `sudo nixos-generate-config --root /mnt` and replace
   `machines/tower/hardware-configuration.nix` with the generated
   `/mnt/etc/nixos/hardware-configuration.nix`. Confirm `system.stateVersion`
   against the installer release before the first installation.
5. Include all new files in the Git source used for the flake. Build and install
   with `sudo nixos-install --flake .#tower` from that checkout. The pinned
   private flake inputs may require access from the build machine.
6. Reboot and verify `ssh luna@<LAN-IP>`. Enrol with
   `sudo tailscale up --accept-dns=false`, then verify `ssh luna@tower`.

Use this manual installation flow for the bootstrap; `scripts/install.sh`
assumes the older hosts' VPN and disk-provisioning setup.

## Installed system

First boot verified on 2026-11-22: NixOS 26.11, kernel 6.18.62,
NVIDIA driver 595.112.07 (16,303 MiB VRAM), Codex 0.167.0, T3 Code 0.1.7.
SSH is available at `luna@10.0.0.161` on the LAN; DHCP may change this address.
The initial configuration snapshot is `/etc/nixos/source` on Tower, so before
adopting the committed deployment workflow rebuild with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos/source#tower
```

Tower is enrolled as `tag:server` at `100.75.169.97`
(`tower.tail3275e2.ts.net`). Initial enrolment used a single-use, short-lived
key generated through the homelab OAuth client. Only Tailscale's own node state
remains on Tower; no OAuth client secret or reusable auth key was installed.
State persists across reboots. After a reinstall, enrol the node again.

## Local screen and fleet monitoring

The 3440×1440 monitor opens a passive dark dashboard automatically. Tower,
Nova, Pulsar, and Comet occupy a 2×2 grid; Lake fills the right column. Offline
hosts are compact footer entries, with Gateway in a compact status row. No
keyboard, mouse, tabs, or rotation is needed. Cards show CPU/GPU/network history,
memory and system disk used/total, temperatures, disk activity, and uptime.
Online badges are green; card backgrounds stay neutral charcoal.

The collector is Go, shared from
`machines/gateway/packages/hardware-telemetry` so Gateway's standalone flake
can build the same source. Each host samples every two seconds. NVIDIA uses
nvidia-smi, Lake uses AMD sysfs counters, Nova uses i915 PMU engine counters
(the service receives only CAP_PERFMON), and Apple silicon uses unprivileged
IORegistry AGX statistics. Intel usage is the busiest engine, not the sum of
concurrent engines. Apple GPU memory is used/shared system capacity, not
separate VRAM; AMD reports reserved UMA. Unsupported fields remain unavailable,
and a missing hardware GPU is distinguished from failed collection.

Lake's ZFS section polls zpool JSON and dataset usage every ten seconds. It
shows pool and scan health, raw used/total, numbered SATA ports, device names,
per-drive capacity, temperature, read/write rates, IOPS, busy time, and
read/write/checksum errors. The old and new members of a replacement share the
same port number. Drive activity comes from kernel counters; temperatures reuse
Lake's existing SMART sensor service. Dataset capacity is used plus currently
available shared space, not dedicated capacity. No storage settings are changed.

Tower's `tower-dashboard.service` binds only `127.0.0.1:8099`. It polls fixed
peer URLs server-side with short timeouts; a failed host does not block others.
Lake, Nova, Pulsar and Comet expose read-only metrics on their private LAN
addresses, restricted to Tower's source address. Linux also enforces this in
the firewall. Addresses must remain stable. The endpoints have no separate API
key: they trust the private network and source-address restrictions. Gateway
binds only its NetBird address and accepts Lake, which relays its metrics to
Tower; this requires a Lake-to-Gateway TCP 8099 NetBird policy. Gilbert and Void
have collector configurations, but deployment awaits their return online.

Macs have a nix-darwin user LaunchAgent module. Before their next full Darwin
activation, `scripts/install-mac-telemetry.sh` installs the same Go executable
as a per-user LaunchAgent without sudo. Remove the bootstrap plist before
adopting the nix-darwin-managed agent to avoid duplicate launchd labels.

`cage-tty1.service` runs Chromium as the dedicated unprivileged dashboard user.
Software rendering preserves GPU memory for inference. The screen stays awake;
the kiosk restarts if closed. Stale samples become offline; missing readings do
not become zero. Use Ctrl+Alt+F2 for a login console and Alt+F1 to return.

## Coding access

T3 starts as `luna` with `~/code` as its working directory and `~/.t3` as its
state directory. It shares `luna`'s Codex configuration and credentials.
The package versions match the repo's pinned Lake tooling.

- T3 accepts private-network connections on port 3773 through the LAN and
  Tailscale interfaces. Client pairing is required.
- Open `http://10.0.0.161:3773` on the LAN or `http://100.75.169.97:3773`
  from an enrolled device. Pair your browser
  or T3 client using `ssh -t luna@tower t3 pair`; keep its short-lived
  pairing token out of chat and repository files.
- Without VPN access, use `ssh -L 3773:127.0.0.1:3773 luna@10.0.0.161` and
  connect through local port 3773.
- The `NixOS configs` workspace is at `~/code/nixos-configs`, checked out on
  the installation PR branch.
- Inspect health with `systemctl status t3code` and `journalctl -u t3code`.
- Codex defaults to the local `tower` provider, with no cloud API credentials.
  Run `codex` as `luna` in a project directory.
- T3 seeds its default model and Codex provider settings on first start only;
  subsequent UI preferences are preserved. Its provider probe reports `ready`.
- System-wide Codex defaults and the model catalog are managed in `codex.nix`.
  User-level overrides in `~/.codex/config.toml` take precedence.
- Once installed and these changes are committed, deploy with
  `python3 scripts/deploy.py tower --target luna@<LAN-IP>` until the VPN name works.

## Local inference

`inkling.service` runs **AtomicChat/Inkling-2-Mini-Uncensored-GGUF**, the
abliterated variant of [Inkling 2 Mini](https://thinkingmachines.ai/news/inkling-2-mini/),
in the `AD-IQ3_S` quantization. The 13.34 GB model is pinned to Hugging Face
revision `40886ab636cabb4decf4998224f790b462ab048e` and verified by SHA-256.
The upstream llama.cpp `b12633` CUDA 12.8 binaries and runtime are also
hash-pinned and patched for NixOS in `packages/llama-cpp-cuda`.

- Model ID: `inkling-2-mini-abliterated`.
- OpenAI-compatible base URLs: `http://10.0.0.161:8080/v1` (LAN) or
  `http://100.75.169.97:8080/v1` (Tailscale).
- Supports `/v1/chat/completions` and `/v1/responses`, including tool calls.
- 32,768-token context, Q8 KV cache, one concurrent slot, all layers on GPU.
  Observed GPU memory use after testing: 14,118 MiB of 16,303 MiB. Long requests queue behind the active request.
- Text only: no vision projector is installed, and Codex advertises text input.
- Access is restricted by the firewall to the LAN interface and Tailscale;
  the inference endpoint does not require an API key. No router port forwards
  or public ingress were added.
- Health: `curl http://127.0.0.1:8080/health` on Tower.
- Logs: `journalctl -u inkling`; GPU status: `nvidia-smi`.

Validation on 2026-11-22: both API routes returned valid output; a forced
function call produced the expected JSON arguments; Codex inspected a small
JavaScript fixture, fixed its incorrect initial accumulator, and executed
its unchanged Node assertions successfully. T3 discovered this model as its
only Codex model and reported the provider ready. These are smoke tests,
not a benchmark or a guarantee of model quality on larger coding tasks.
