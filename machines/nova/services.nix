{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_oauth = {};
      pihole_password = {};
      rustfs_env = {};
      brrr_token = {};
      romm_env = {};
      rustic_password = {};
      immich_env = {};
    };
  };
}