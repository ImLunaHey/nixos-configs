{ config, pkgs, ... }:

let
  atm10ServerPack = pkgs.stdenv.mkDerivation {
    pname = "atm10-server-pack";
    version = "4.14";

    src = pkgs.fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7121/795/ServerFiles-4.14.zip";
      hash = "sha256-jphu2VEN3CVSdgaduyCAUAxaugwJ/UVrBIQYEmVMhaE=";
    };

    nativeBuildInputs = [ pkgs.unzip ];

    unpackPhase = ''
      unzip $src -d .
    '';

    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d /srv/minecraft 0755 minecraft minecraft -"
    "d /srv/minecraft/atm10 0755 minecraft minecraft -"
  ];

  users.users.minecraft = {
    isSystemUser = true;
    group = "minecraft";
    home = "/srv/minecraft";
  };
  users.groups.minecraft = {};

  systemd.services.atm10 = {
    description = "All the Mods 10 Minecraft Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      User = "minecraft";
      WorkingDirectory = "/srv/minecraft/atm10";

      # On first run, sync the server pack files and install NeoForge
      ExecStartPre = pkgs.writeShellScript "atm10-setup" ''
        # Sync server pack files if not already present
        if [ ! -f /srv/minecraft/atm10/user_jvm_args.txt ]; then
          echo "Syncing server pack files..."
          cp -rn ${atm10ServerPack}/. /srv/minecraft/atm10/
          chmod -R u+w /srv/minecraft/atm10/
        fi

        # Install NeoForge if not already installed
        if [ ! -d /srv/minecraft/atm10/libraries ]; then
          echo "Installing NeoForge..."
          cd /srv/minecraft/atm10
          ${pkgs.jdk21}/bin/java -jar neoforge-21.1.211-installer.jar -installServer
        fi

        # Write eula.txt
        echo "eula=true" > /srv/minecraft/atm10/eula.txt
      '';

      ExecStart = "${pkgs.jdk21}/bin/java @user_jvm_args.txt @libraries/net/neoforged/neoforge/21.1.211/unix_args.txt nogui";
      ExecStop = pkgs.writeShellScript "atm10-stop" ''
        ${pkgs.mcrcon}/bin/mcrcon -H localhost -P 25575 -p "$(cat ${config.sops.secrets.rcon_password.path})" stop
      '';
      Restart = "on-failure";
      RestartSec = "30s";
      OOMScoreAdjust = -500;
    };

    environment = {
      JAVA_HOME = "${pkgs.jdk21}";
    };
  };

  system.activationScripts.minecraft-config = {
    deps = [ "setupSecrets" ];
    text = ''
      if [ -f /srv/minecraft/atm10/server.properties ]; then
        ${pkgs.gnused}/bin/sed -i \
          's/enable-rcon=false/enable-rcon=true/' \
          /srv/minecraft/atm10/server.properties
        ${pkgs.gnused}/bin/sed -i \
          "s/rcon\.password=.*/rcon.password=$(cat ${config.sops.secrets.rcon_password.path})/" \
          /srv/minecraft/atm10/server.properties
      fi
    '';
  };

  networking.firewall.allowedTCPPorts = [ 25565 ];
  networking.firewall.allowedUDPPorts = [ 25565 ];

  environment.systemPackages = [ pkgs.jdk21 pkgs.mcrcon ];
}