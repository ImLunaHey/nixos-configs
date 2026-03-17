{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  # Required by ZFS — generate with: head -c 8 /etc/machine-id
  # Or: printf "%08x" $RANDOM$RANDOM
  networking.hostId = "73873532";
}
