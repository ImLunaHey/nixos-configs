{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_oauth = { };
      gotify_upgrade_token = { };
    };
  };
}
