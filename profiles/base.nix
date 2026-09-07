{ config, lib, pkgs, ... }:
let
  cfg = config.homelabBase;
in
{
  options.homelabBase = {
    user = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Administrative user to create, or null to manage users elsewhere.";
      };
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Literal SSH public keys for the administrative user.";
      };
      authorizedKeyFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Files containing SSH public keys for the administrative user.";
      };
      passwordlessSudo = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow members of wheel to use sudo without a password.";
      };
    };

    ssh.enable = lib.mkEnableOption "key-only OpenSSH access";

    vpn.provider = lib.mkOption {
      type = lib.types.enum [ "none" "tailscale" "netbird" ];
      default = "none";
      description = "Mesh VPN client to enable.";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
      description = "Default system locale.";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/London";
      description = "System time zone.";
    };

    autoUpgrade = {
      enable = lib.mkEnableOption "automatic flake upgrades";
      flake = lib.mkOption { type = lib.types.str; default = ""; description = "Flake URI passed to nixos-rebuild."; };
      dates = lib.mkOption { type = lib.types.str; default = "daily"; description = "systemd calendar expression for upgrades."; };
      randomizedDelaySec = lib.mkOption { type = lib.types.str; default = "1h"; description = "Random delay applied to the upgrade timer."; };
      allowReboot = lib.mkOption { type = lib.types.bool; default = false; description = "Allow automatic upgrades to reboot the host."; };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [{
        assertion = !cfg.autoUpgrade.enable || cfg.autoUpgrade.flake != "";
        message = "homelabBase.autoUpgrade.flake must be set when automatic upgrades are enabled";
      }];
      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
        allowed-users = [ "@wheel" "root" ];
      };
      time.timeZone = cfg.timeZone;
      i18n.defaultLocale = cfg.locale;
      environment.systemPackages = with pkgs; [ nano tree git btop wget curl ];
      users.mutableUsers = false;
      users.users.root.hashedPassword = "!";
      security.sudo.wheelNeedsPassword = !cfg.user.passwordlessSudo;
    }

    (lib.mkIf (cfg.user.name != null) {
      users.users.${cfg.user.name} = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys = {
          keys = cfg.user.authorizedKeys;
          keyFiles = cfg.user.authorizedKeyFiles;
        };
      };
    })

    (lib.mkIf cfg.ssh.enable {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
        listenAddresses = [
          { addr = "0.0.0.0"; port = 22; }
          { addr = "[::]"; port = 22; }
        ];
      };
    })

    (lib.mkIf (cfg.vpn.provider == "tailscale") {
      services.tailscale = { enable = true; useRoutingFeatures = "client"; };
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf cfg.ssh.enable [ 22 ];
    })

    (lib.mkIf (cfg.vpn.provider == "netbird") {
      services.netbird.enable = true;
      networking.firewall.interfaces.wt0.allowedTCPPorts = lib.mkIf cfg.ssh.enable [ 22 ];
    })

    (lib.mkIf cfg.autoUpgrade.enable {
      system.autoUpgrade = {
        enable = true;
        inherit (cfg.autoUpgrade) flake dates randomizedDelaySec allowReboot;
      };
    })
  ];
}
