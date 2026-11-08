{ brrrNotify, pkgs, ... }:
let
  healthCheck = pkgs.writeShellApplication {
    name = "lake-health-check";
    runtimeInputs = with pkgs; [ coreutils gnugrep postgresql_18 systemd util-linux zfs ];
    text = ''
      state_dir=/var/lib/lake-health-monitor
      previous="$state_dir/failures"
      current=$(mktemp "$state_dir/failures.XXXXXX")
      trap 'rm -f "$current"' EXIT

      record_failure() {
        echo "$1" >> "$current"
      }

      systemctl is-active --quiet docker-lancache.service || record_failure lancache
      systemctl is-active --quiet anvil.service || record_failure anvil
      systemctl is-active --quiet anvil-agent.service || record_failure anvil-agent

      agent_fresh=$(runuser -u anvil -- psql -d anvil -Atc \
        "SELECT COALESCE(bool_or(last_seen_at > now() - interval '2 minutes'), false) FROM hosts WHERE name = 'lake';" \
        2>/dev/null || echo f)
      [ "$agent_fresh" = t ] || record_failure anvil-registration

      used=$(zfs get -Hp -o value used storage/lancache 2>/dev/null || echo 0)
      quota=$(zfs get -Hp -o value quota storage/lancache 2>/dev/null || echo 0)
      if [ "$quota" -gt 0 ] && [ $((used * 100 / quota)) -ge 90 ]; then
        record_failure lancache-capacity
      fi

      sort -u -o "$current" "$current"
      touch "$previous"

      describe() {
        case "$1" in
          lancache) echo "Lancache is not running" ;;
          anvil) echo "Anvil is not running" ;;
          anvil-agent) echo "The Anvil agent service is not running" ;;
          anvil-registration) echo "Lake's Anvil agent has stopped checking in" ;;
          lancache-capacity) echo "Lancache has reached 90% of its 500GB quota" ;;
        esac
      }

      while read -r failure; do
        [ -n "$failure" ] || continue
        if ! grep -Fxq "$failure" "$previous"; then
          ${brrrNotify} "Lake service alert" "$(describe "$failure")" time-sensitive warm_soft_error lake
        fi
      done < "$current"

      while read -r recovered; do
        [ -n "$recovered" ] || continue
        if ! grep -Fxq "$recovered" "$current"; then
          ${brrrNotify} "Lake service recovered" "$(describe "$recovered")" active bubbly_success_ding lake
        fi
      done < "$previous"

      mv "$current" "$previous"
      trap - EXIT
    '';
  };
in
{
  systemd.services.lake-health-monitor = {
    description = "Monitor Lake application health";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "lake-health-monitor";
      ExecStart = pkgs.lib.getExe healthCheck;
    };
  };

  systemd.timers.lake-health-monitor = {
    description = "Check Lake application health every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      Unit = "lake-health-monitor.service";
    };
  };
}
