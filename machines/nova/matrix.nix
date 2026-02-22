{ config, pkgs, ... }:
{
  sops.secrets.matrix_registration_secret = {
    owner = "matrix-synapse";
  };

  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = "nova.flaked.org";
      public_baseurl = "https://nova.flaked.org";
      listeners = [{
        port = 8008;
        bind_addresses = [ "127.0.0.1" ];
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [{
          names = [ "client" "federation" ];
          compress = false;
        }];
      }];
      registration_shared_secret_path = config.sops.secrets.matrix_registration_secret.path;
    };
  };

  services.postgresql = {
    enable = true;
    initialScript = pkgs.writeText "matrix-pg-init" ''
      CREATE DATABASE "matrix-synapse"
        ENCODING 'UTF8'
        LC_COLLATE 'C'
        LC_CTYPE 'C'
        TEMPLATE template0;
      CREATE USER "matrix-synapse";
      GRANT ALL PRIVILEGES ON DATABASE "matrix-synapse" TO "matrix-synapse";
    '';
  };
}