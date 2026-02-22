{ config, ... }:
{
  sops.secrets.matrix_registration_secret = {
    owner = "matrix-synapse";
  };

  sops.secrets.cloudflare_api_token = {};

  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = "nova.tail3275e2.ts.net";
      public_baseurl = "https://nova.tail3275e2.ts.net";
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
}