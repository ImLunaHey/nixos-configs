{ config, lib, pkgs, ... }:
let
  lanAddress = "10.0.0.46";
  baoAddress = "https://openbao.home.arpa:8200";
  bootstrapAddress = "https://127.0.0.1:8200";
  bootstrapDirectory = "/var/lib/openbao-bootstrap";
  tlsDirectory = "${bootstrapDirectory}/tls";
  credentialDirectory = "/run/credentials/openbao.service";

  initializeOpenBao = pkgs.writeShellApplication {
    name = "openbao-init";
    runtimeInputs = with pkgs; [ coreutils jq openbao ];
    text = ''
      set -euo pipefail
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run openbao-init as root." >&2
        exit 1
      fi

      export BAO_ADDR=${lib.escapeShellArg bootstrapAddress}
      export BAO_CACERT=${lib.escapeShellArg "${tlsDirectory}/ca.crt"}
      output=${lib.escapeShellArg "${bootstrapDirectory}/init.json"}

      if ${pkgs.openbao}/bin/bao status -format=json 2>/dev/null | ${pkgs.jq}/bin/jq -e '.initialized' >/dev/null; then
        echo "OpenBao is already initialized."
        exit 0
      fi

      if [ -e "$output" ]; then
        echo "$output already exists, refusing to overwrite recovery material." >&2
        exit 1
      fi

      umask 077
      ${pkgs.openbao}/bin/bao operator init \
        -format=json \
        -recovery-shares=5 \
        -recovery-threshold=3 > "$output"
      chmod 0600 "$output"

      echo "OpenBao initialized. Recovery keys and the initial root token are in $output."
      echo "Back that file up offline before migrating secrets."
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.openbao
    initializeOpenBao
  ];

  networking.extraHosts = ''
    ${lanAddress} openbao.home.arpa
  '';

  services.openbao = {
    enable = true;
    settings = {
      ui = true;
      # Keep an uninitialized vault unreachable from the network. The cutover
      # changes this to the LAN address only after initialization and migration.
      api_addr = bootstrapAddress;
      cluster_addr = "https://127.0.0.1:8201";

      listener.default = {
        type = "tcp";
        address = "127.0.0.1:8200";
        cluster_address = "127.0.0.1:8201";
        tls_cert_file = "${credentialDirectory}/tls-cert";
        tls_key_file = "${credentialDirectory}/tls-key";
        tls_min_version = "tls13";
      };

      storage.raft = {
        path = "/var/lib/openbao";
        node_id = "lake";
      };

      seal.static = {
        current_key_id = "lake-host-key-v1";
        current_key = "file:///run/openbao/seal.key";
      };
    };
  };

  systemd.services.openbao-bootstrap-tls = {
    description = "Create Lake's private OpenBao certificate authority";
    wantedBy = [ "multi-user.target" ];
    before = [ "openbao.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/install -d -m 0700 ${tlsDirectory}

      ca_created=0
      if [ ! -s ${tlsDirectory}/ca.key ] || [ ! -s ${tlsDirectory}/ca.crt ]; then
        ${pkgs.coreutils}/bin/rm -f \
          ${tlsDirectory}/ca.key \
          ${tlsDirectory}/ca.crt \
          ${tlsDirectory}/ca.srl \
          ${tlsDirectory}/server.key \
          ${tlsDirectory}/server.crt
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
          -days 3650 \
          -subj /CN=Lake\ OpenBao\ CA \
          -keyout ${tlsDirectory}/ca.key \
          -out ${tlsDirectory}/ca.crt
        ca_created=1
      fi

      if [ "$ca_created" -eq 1 ] || [ ! -s ${tlsDirectory}/server.key ] || [ ! -s ${tlsDirectory}/server.crt ]; then
        ${pkgs.openssl}/bin/openssl req -new -newkey rsa:3072 -sha256 -nodes \
          -subj /CN=openbao.home.arpa \
          -keyout ${tlsDirectory}/server.key \
          -out ${tlsDirectory}/server.csr
        ${pkgs.openssl}/bin/openssl x509 -req -sha256 -days 825 \
          -in ${tlsDirectory}/server.csr \
          -CA ${tlsDirectory}/ca.crt \
          -CAkey ${tlsDirectory}/ca.key \
          -CAcreateserial \
          -extfile <(${pkgs.coreutils}/bin/printf '%s\n' \
            'subjectAltName=DNS:openbao.home.arpa,DNS:lake,IP:${lanAddress},IP:127.0.0.1' \
            'extendedKeyUsage=serverAuth') \
          -out ${tlsDirectory}/server.crt
        ${pkgs.coreutils}/bin/rm -f ${tlsDirectory}/server.csr
      fi

      chmod 0600 ${tlsDirectory}/ca.key ${tlsDirectory}/server.key
      chmod 0644 ${tlsDirectory}/ca.crt ${tlsDirectory}/server.crt
    '';
  };

  systemd.services.openbao = {
    requires = [ "openbao-bootstrap-tls.service" ];
    after = [
      "openbao-bootstrap-tls.service"
      "sshd-keygen.target"
    ];
    serviceConfig = {
      LoadCredential = [
        "seal-source:/etc/ssh/ssh_host_ed25519_key"
        "tls-cert:${tlsDirectory}/server.crt"
        "tls-key:${tlsDirectory}/server.key"
      ];
      ExecStartPre = pkgs.writeShellScript "openbao-derive-static-seal-key" ''
        set -euo pipefail
        ${pkgs.openssl}/bin/openssl dgst -sha256 -binary \
          "$CREDENTIALS_DIRECTORY/seal-source" > /run/openbao/seal.key
        chmod 0400 /run/openbao/seal.key
      '';
    };
  };
}
