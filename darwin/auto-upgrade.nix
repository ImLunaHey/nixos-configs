{ config, lib, pkgs, ... }:

# Poll the repo and rebuild every 15 minutes, mirroring the NixOS hosts'
# `system.autoUpgrade`. Builds from the default branch's committed flake.lock,
# except for inputs a host explicitly opts into resolving independently.
let
  cfg = config.services.darwinAutoUpgrade;
  flake = "github:imlunahey/nixos-configs";
  host = config.networking.hostName;
  inputOverrideArguments = lib.concatLists (
    lib.mapAttrsToList (
      name: source: [ "--override-input" name source ]
    ) cfg.inputOverrides
  );
  inputOverrides = lib.optionalString (
    inputOverrideArguments != [ ]
  ) " ${lib.escapeShellArgs inputOverrideArguments}";
  sshCommand = lib.optionalString (cfg.sshIdentityFile != null) (
    toString (pkgs.writeShellScript "darwin-auto-upgrade-ssh" ''
      exec /usr/bin/ssh \
        -o BatchMode=yes \
        -o IdentitiesOnly=yes \
        -i ${lib.escapeShellArg cfg.sshIdentityFile} \
        "$@"
    '')
  );
  sshEnvironment = lib.optionalString (sshCommand != "") ''
    export GIT_SSH_COMMAND=${lib.escapeShellArg sshCommand}
  '';
  upgrade = pkgs.writeShellScript "darwin-auto-upgrade" ''
    export PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin
    ${sshEnvironment}
    exec darwin-rebuild switch --refresh${inputOverrides} --flake ${flake}#${host}
  '';
  workerLabel = "org.nixos.darwin-auto-upgrade-worker";
  worker = pkgs.writeShellScript "darwin-auto-upgrade-worker" ''
    export PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin
    ${sshEnvironment}

    cleanup() {
      trap - HUP INT TERM
      /bin/launchctl remove ${lib.escapeShellArg workerLabel} >/dev/null 2>&1 || true
    }
    trap cleanup HUP INT TERM

    status=0
    darwin-rebuild switch --refresh${inputOverrides} --flake ${flake}#${host} || status=$?
    cleanup
    exit "$status"
  '';
  trigger = pkgs.writeShellScript "darwin-auto-upgrade-trigger" ''
    if /bin/launchctl print system/${workerLabel} >/dev/null 2>&1; then
      exit 0
    fi

    exec /bin/launchctl submit \
      -l ${lib.escapeShellArg workerLabel} \
      -o /var/log/darwin-auto-upgrade.log \
      -e /var/log/darwin-auto-upgrade.log \
      -- ${worker}
  '';
in
{
  options.services.darwinAutoUpgrade.inputOverrides = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Flake inputs to resolve independently during each automatic upgrade.";
  };
  options.services.darwinAutoUpgrade.sshIdentityFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Runtime SSH identity path for private flake inputs; the key is not copied into the Nix store.";
  };

  config = {
    # Keep the legacy job while installing the detached scheduler. A follow-up
    # removes it after the scheduler is live on Pulsar.
    launchd.daemons.darwin-auto-upgrade = {
      serviceConfig = {
        ProgramArguments = [ "${upgrade}" ];
        StartInterval = 900; # every 15 minutes
        RunAtLoad = false; # don't re-trigger a rebuild during activation
        StandardOutPath = "/var/log/darwin-auto-upgrade.log";
        StandardErrorPath = "/var/log/darwin-auto-upgrade.log";
      };
    };
    launchd.daemons.darwin-auto-upgrade-scheduler = {
      serviceConfig = {
        ProgramArguments = [ "${trigger}" ];
        StartInterval = 900;
        RunAtLoad = false;
        StandardOutPath = "/var/log/darwin-auto-upgrade.log";
        StandardErrorPath = "/var/log/darwin-auto-upgrade.log";
      };
    };
  };
}
