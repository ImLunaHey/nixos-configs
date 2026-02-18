{ config, pkgs, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_key = { };
      makemkv_key = { };
      omdb_api_key = { };
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets.tailscale_key.path;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }
      { addr = "[::]"; port = 22; }
    ];
  };

  system.activationScripts.arm-config = {
    deps = [ "setupSecrets" ];
    text = ''
      ${pkgs.gnused}/bin/sed \
        -e "s|@MAKEMKV_KEY@|$(cat ${config.sops.secrets.makemkv_key.path})|g" \
        -e "s|@OMDB_API_KEY@|$(cat ${config.sops.secrets.omdb_api_key.path})|g" \
        ${./arm-config/arm.yaml} > /mnt/media/config/arm.yaml
      chown 1000:1000 /mnt/media/config/arm.yaml
      chmod 644 /mnt/media/config/arm.yaml
    '';
  };
}