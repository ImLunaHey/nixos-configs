{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_key = {};
      pihole_password = {};
    };
    matrix_registration_secret = {
      owner = "matrix-synapse";
    };
  };
}