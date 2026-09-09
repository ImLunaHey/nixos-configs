{ lib, pkgs, ... }:
let
  asterctl = pkgs.stdenvNoCC.mkDerivation {
    pname = "asterctl";
    version = "0.2.0-unstable-2026-09-07";

    src = pkgs.fetchurl {
      url = "https://github.com/zehnm/aoostar-rs/releases/download/latest/asterctl-v0.2.0-6-g2f4d959-Linux-x64-20250917_193843.tar.gz";
      hash = "sha256-ONYrgSHiTWvDcfGtpyY0MxSBXm3J+ZcB5RJ4iww/iwo=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.systemd pkgs.stdenv.cc.cc.lib ];

    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      install -Dm755 asterctl $out/bin/asterctl
      runHook postInstall
    '';

    meta = {
      description = "Open screen control for the AOOSTAR WTR MAX";
      homepage = "https://github.com/zehnm/aoostar-rs";
      license = with lib.licenses; [ mit asl20 ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "asterctl";
    };
  };

  dashboardConfig = pkgs.writeText "lake-display.json" (builtins.toJSON {
    setup = {
      switchTime = "3600";
      refresh = 2;
    };
    mianban = [ 1 ];
    diy = [{
      id = "lake";
      name = "Lake status";
      img = null;
      sensor = let
        line = label: y: size: color: {
          mode = 1;
          type = null;
          name = null;
          itemName = null;
          inherit label y;
          value = null;
          minValue = null;
          maxValue = null;
          unit = null;
          x = 36;
          width = 888;
          height = 44;
          direction = null;
          fontFamily = "DejaVuSans";
          fontSize = size;
          fontColor = color;
          fontWeight = null;
          textAlign = "left";
          integerDigits = null;
          decimalDigits = null;
          pic = null;
          minAngle = null;
          maxAngle = null;
          xz_x = null;
          xz_y = null;
        };
      in [
        (line "title" 14 32 "#63d8ff")
        (line "temperatures" 62 22 "#ffffff")
        (line "drives" 108 21 "#ffffff")
        (line "pool" 154 22 "#80ff9d")
        (line "capacity" 200 21 "#ffffff")
        (line "services" 246 21 "#ffffff")
        (line "cache" 292 20 "#ffffff")
        (line "network" 338 20 "#ffffff")
        (line "uptime" 382 18 "#aeb8c4")
      ];
    }];
  });

  collectSensors = pkgs.writeShellApplication {
    name = "lake-display-collect";
    runtimeInputs = with pkgs; [ coreutils gawk gnused iproute2 postgresql_18 smartmontools systemd util-linux zfs ];
    text = ''
      read_temp() {
        local name="$1"
        local hw
        for hw in /sys/class/hwmon/hwmon*; do
          if [ "$(cat "$hw/name" 2>/dev/null || true)" = "$name" ]; then
            awk '{ printf "%.0f", $1 / 1000 }' "$hw/temp1_input"
            return
          fi
        done
        printf -- "--"
      }

      cpu_temp=$(read_temp k10temp)
      gpu_temp=$(read_temp amdgpu)
      nvme_temp=$(read_temp nvme)

      hdd_temps=""
      hdd_count=0
      hdd_max=0
      for disk in /dev/sd?; do
        [ "$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)" -gt 0 ] || continue
        temp=$(smartctl -A "$disk" 2>/dev/null | awk '$1 == 194 { print $10; exit }' || true)
        case "$temp" in
          ""|*[!0-9]*) continue ;;
        esac
        hdd_count=$((hdd_count + 1))
        [ "$temp" -gt "$hdd_max" ] && hdd_max="$temp"
        hdd_temps="''${hdd_temps}''${hdd_temps:+ }''${temp}°"
      done

      if pool_health=$(zpool list -H -o health storage 2>/dev/null); then
        pool_capacity=$(zpool list -H -o capacity storage)
        pool_text="ZFS storage: $pool_health"
        capacity_text="Pool used: $pool_capacity"
      else
        pool_text="ZFS storage: not configured"
        capacity_text="Root used: $(df -h / | awk 'NR == 2 { print $5 }')"
      fi

      anvil_state=$(systemctl is-active anvil.service 2>/dev/null || true)
      agent_state=$(systemctl is-active anvil-agent.service 2>/dev/null || true)
      agent_fresh=$(runuser -u anvil -- psql -d anvil -Atc \
        "SELECT COALESCE(bool_or(last_seen_at > now() - interval '2 minutes'), false) FROM hosts WHERE name = 'lake';" \
        2>/dev/null || echo f)
      if [ "$anvil_state" = active ] && [ "$agent_state" = active ] && [ "$agent_fresh" = t ]; then
        services_text="Anvil: healthy    agent: connected"
      else
        services_text="Anvil: ''${anvil_state:-unknown}    agent: disconnected"
      fi

      if systemctl is-active --quiet docker-lancache.service; then
        cache_usage=$(zfs list -H -o used,quota storage/lancache 2>/dev/null | awk '{ print $1 "/" $2 }')
        hit_percent=$(
          tail -n 20000 /mnt/storage/lancache/logs/access.log 2>/dev/null \
            | awk '/"HIT"/ { h++ } /"MISS"/ { m++ } END { printf "%d", (h + m ? 100 * h / (h + m) : 0) }'
        )
        cache_text="Lancache: ''${cache_usage:-unknown}    hit ''${hit_percent:-0}%"
      else
        cache_text="Lancache: offline"
      fi

      lan_ip=$(ip -4 -o addr show dev enp100s0f1np1 | awk '{ split($4, a, "/"); print a[1]; exit }')
      link_speed=$(cat /sys/class/net/enp100s0f1np1/speed 2>/dev/null || echo unknown)
      if [ "$link_speed" = "10000" ]; then link_speed="10 Gb/s"; else link_speed="''${link_speed} Mb/s"; fi

      uptime_seconds=$(awk '{ print int($1) }' /proc/uptime)
      uptime_days=$((uptime_seconds / 86400))
      uptime_hours=$(((uptime_seconds % 86400) / 3600))
      uptime_minutes=$(((uptime_seconds % 3600) / 60))
      if [ "$uptime_days" -gt 0 ]; then
        uptime_text="Up ''${uptime_days}d ''${uptime_hours}h ''${uptime_minutes}m"
      else
        uptime_text="Up ''${uptime_hours}h ''${uptime_minutes}m"
      fi

      tmp=$(mktemp /run/lake-display/sensors.XXXXXX)
      {
        echo "title: LAKE"
        echo "temperatures: CPU ''${cpu_temp}°C    GPU ''${gpu_temp}°C    NVMe ''${nvme_temp}°C"
        echo "drives: HDDs ($hdd_count) ''${hdd_temps:-no readings}    max ''${hdd_max}°C"
        echo "pool: $pool_text"
        echo "capacity: $capacity_text"
        echo "services: $services_text"
        echo "cache: $cache_text"
        echo "network: ''${lan_ip:-no IPv4}    $link_speed"
        echo "uptime: $uptime_text"
      } > "$tmp"
      chmod 0644 "$tmp"
      mv "$tmp" /run/lake-display/sensors.txt
    '';
  };
in
{
  environment.systemPackages = [ asterctl ];

  systemd.services.lake-display-sensors = {
    description = "Collect Lake LCD dashboard sensors";
    wantedBy = [ "multi-user.target" ];
    before = [ "lake-display.service" ];
    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "lake-display";
      RuntimeDirectoryMode = "0755";
      ExecStart = pkgs.writeShellScript "lake-display-sensor-loop" ''
        while true; do
          ${lib.getExe collectSensors}
          sleep 10
        done
      '';
      Restart = "always";
      RestartSec = 2;
    };
  };

  systemd.services.lake-display = {
    description = "AOOSTAR Lake status display";
    wantedBy = [ "multi-user.target" ];
    after = [ "lake-display-sensors.service" ];
    requires = [ "lake-display-sensors.service" ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      SupplementaryGroups = [ "dialout" ];
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe asterctl)
        "--device /dev/ttyACM0"
        "--config ${dashboardConfig}"
        "--font-dir ${pkgs.dejavu_fonts}/share/fonts/truetype"
        "--sensor-path /run/lake-display"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      DevicePolicy = "closed";
      DeviceAllow = [ "/dev/ttyACM0 rw" ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
