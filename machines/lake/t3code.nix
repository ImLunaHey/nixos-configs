{ config, pkgs, t3codePkgs, ... }:
let
  user = config.users.users.luna;
  codeDirectory = "${user.home}/code";
  bindAddress = "0.0.0.0";
  port = 3773;
  lumenT3CodeAppId = "5263887";
  lumenT3CodeInstallationId = "169973417";
  t3code = t3codePkgs.callPackage ../../packages/t3code { };
  pnpm_12 = t3codePkgs.callPackage ../../packages/pnpm-12 { };
  lumenT3CodeToken = pkgs.writeShellApplication {
    name = "lumen-t3code-token";
    runtimeInputs = with pkgs; [ coreutils curl jq openssl ];
    text = ''
      set -euo pipefail
      umask 077

      key_file="''${LUMEN_T3CODE_PRIVATE_KEY_FILE:-/run/secrets/lumen_t3code_private_key}"
      app_id="''${LUMEN_T3CODE_APP_ID:-${lumenT3CodeAppId}}"
      installation_id="''${LUMEN_T3CODE_INSTALLATION_ID:-${lumenT3CodeInstallationId}}"

      if [[ ! -r "$key_file" ]]; then
        echo "GitHub App private key is not readable: $key_file" >&2
        exit 1
      fi

      base64url() {
        openssl base64 -A | tr '+/' '-_' | tr -d '='
      }

      now="$(date +%s)"
      issued_at="$((now - 60))"
      expires_at="$((now + 540))"
      header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)"
      payload="$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' \
        "$issued_at" "$expires_at" "$app_id" | base64url)"
      unsigned_token="$header.$payload"
      signature="$(printf '%s' "$unsigned_token" \
        | openssl dgst -sha256 -sign "$key_file" -binary \
        | base64url)"
      jwt="$unsigned_token.$signature"

      curl --fail-with-body --silent --show-error \
        --request POST \
        --header 'Accept: application/vnd.github+json' \
        --header "Authorization: Bearer $jwt" \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        "https://api.github.com/app/installations/$installation_id/access_tokens" \
        | jq --exit-status --raw-output '.token'
    '';
  };
  lumenT3CodeGh = pkgs.writeShellApplication {
    name = "lumen-t3code-gh";
    runtimeInputs = [ lumenT3CodeToken t3codePkgs.gh ];
    text = ''
      set -euo pipefail
      GH_TOKEN="$(lumen-t3code-token)"
      export GH_TOKEN
      exec gh "$@"
    '';
  };
  lumenT3CodeGit = pkgs.writeShellApplication {
    name = "lumen-t3code-git";
    runtimeInputs = [ lumenT3CodeToken pkgs.coreutils pkgs.git ];
    text = ''
      set -euo pipefail
      umask 077

      askpass="$(mktemp)"
      trap 'rm -f "$askpass"' EXIT
      # The single-quoted lines are intentionally written verbatim to the
      # temporary askpass script, where the token variable is evaluated.
      # shellcheck disable=SC2016
      printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  *Username*) printf "%s\\n" "x-access-token" ;;' \
        '  *) printf "%s\\n" "$LUMEN_T3CODE_INSTALLATION_TOKEN" ;;' \
        'esac' >"$askpass"
      chmod 0700 "$askpass"

      LUMEN_T3CODE_INSTALLATION_TOKEN="$(lumen-t3code-token)"
      export LUMEN_T3CODE_INSTALLATION_TOKEN
      export GIT_ASKPASS="$askpass"
      export GIT_TERMINAL_PROMPT=0
      git \
        -c 'url.https://github.com/.insteadOf=git@github.com:' \
        -c 'url.https://github.com/.insteadOf=ssh://git@github.com/' \
        "$@"
    '';
  };
  botTools = [ lumenT3CodeToken lumenT3CodeGh lumenT3CodeGit ];
  developmentTools = with t3codePkgs; [
    cargo
    clippy
    cmake
    codex
    gcc
    gh
    gnumake
    nodejs_24
    pkg-config
    pnpm_12
    rust-analyzer
    rustc
    rustfmt
  ];
in
{
  environment.systemPackages = [ t3code ] ++ developmentTools ++ botTools ++ [ t3codePkgs.ripgrep ];

  # T3 downloads a generic Linux Chrome Headless Shell for browser previews.
  # Let that dynamically linked binary run on NixOS and provide its runtime
  # libraries through nix-ld.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      alsa-lib
      at-spi2-core
      dbus
      expat
      glib
      libgbm
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      nspr
      nss
      systemd
    ];
  };

  sops.secrets.lumen_t3code_private_key = {
    owner = "luna";
    group = user.group;
    mode = "0400";
    restartUnits = [ "t3code.service" ];
  };

  # Lake's root filesystem (including /home) is on the 2 TB NVMe SSD.
  systemd.tmpfiles.rules = [
    "d ${codeDirectory} 0750 luna ${user.group} -"
    "d ${user.home}/.t3 0700 luna ${user.group} -"
  ];

  systemd.services.t3code = {
    description = "T3 Code coding workspace";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
      "tailscale-autoauth.service"
      "systemd-tmpfiles-setup.service"
    ];
    wants = [ "network-online.target" "tailscale-autoauth.service" ];
    unitConfig = {
      RequiresMountsFor = [ user.home ];
      # Keep retrying if networking is unavailable during startup.
      StartLimitIntervalSec = 0;
    };

    environment = {
      HOME = user.home;
      LUMEN_T3CODE_APP_ID = lumenT3CodeAppId;
      LUMEN_T3CODE_INSTALLATION_ID = lumenT3CodeInstallationId;
      LUMEN_T3CODE_PRIVATE_KEY_FILE = config.sops.secrets.lumen_t3code_private_key.path;
    };
    path = (with pkgs; [
      bashInteractive
      coreutils
      findutils
      git
      gnugrep
      gnused
      openssh
      ripgrep
    ]) ++ developmentTools ++ botTools;

    serviceConfig = {
      User = "luna";
      Group = user.group;
      WorkingDirectory = codeDirectory;
      # Run the headless server; device pairing is managed separately with `t3 pair`.
      # T3 Connect terminates its tunnel on loopback, while direct clients use
      # Lake's Tailscale address. Bind both; the firewall only exposes this port
      # on tailscale0.
      ExecStart = "${t3code}/bin/t3 serve --host ${bindAddress} --port ${toString port} --base-dir ${user.home}/.t3";
      Restart = "always";
      RestartSec = "5s";
      UMask = "0027";
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
