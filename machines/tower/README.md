# Tower

`nixosConfigurations.tower` is the headless x86_64 gaming-PC configuration.
It provides DHCP, key-only SSH for `luna`, passwordless sudo, a manually enrolled
Tailscale client, Codex, and T3 Code. The administrative public key is the same
checked-in key used by Gateway. Confirm that the installing client has its
corresponding private key before rebooting.

Tower imports `profiles/base.nix` directly: initial boot does not need SOPS,
OAuth credentials, NAS mounts, or existing homelab services. Automatic upgrades
are disabled. There is no desktop or inference server yet.

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

Tailscale is installed but still requires enrolment. The local model runtime
and Codex provider configuration remain follow-up work.

## Coding access

T3 starts as `luna` with `~/code` as its working directory and `~/.t3` as its
state directory. It shares `luna`'s Codex configuration and credentials.
The package versions match the repo's pinned Lake tooling.

- Direct T3 access on port 3773 is admitted only through `tailscale0`.
- Before VPN enrolment, use `ssh -L 3773:127.0.0.1:3773 luna@<LAN-IP>` and
  connect through local port 3773, or run `t3 pair` as `luna` for T3 Connect.
- Inspect health with `systemctl status t3code` and `journalctl -u t3code`.
- Provider authentication/model configuration still needs completing after boot.
- Once installed and these changes are committed, deploy with
  `python3 scripts/deploy.py tower --target luna@<LAN-IP>` until the VPN name works.

## Local inference follow-up

The requested model is an **abliterated variant of Inkling 2 Mini**, based on
[Thinking Machines' release](https://thinkingmachines.ai/news/inkling-2-mini/).
The exact community checkpoint and quantization are not selected yet.

The GPU driver is configured. Next, select a runtime with support for this
model, pin the selected checkpoint, and allocate VRAM
for both weights and the context cache. Do not assume that a 16 GB GPU can fit
the original checkpoint or a large context alongside quantized weights.

Then expose inference to trusted network clients and configure Codex/T3 to use
it. Verify API compatibility, tool calls, and an actual coding task before
treating that integration as working. No model weights are downloaded and no
inference ports are opened by this bootstrap configuration.
