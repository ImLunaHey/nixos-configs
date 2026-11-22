#!/usr/bin/env bash
# User-session bootstrap for Macs before their next nix-darwin activation.
set -euo pipefail
name=${1:?machine name}
address=${2:?private bind address}
interface=${3:?network interface}
binary=${4:?built Go binary}
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
install -m 0755 "$binary" "$HOME/.local/bin/hardware-telemetry"
plist="$HOME/Library/LaunchAgents/net.luna.hardware-telemetry.plist"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>net.luna.hardware-telemetry</string>
<key>ProgramArguments</key><array><string>$HOME/.local/bin/hardware-telemetry</string></array>
<key>EnvironmentVariables</key><dict>
<key>METRICS_NAME</key><string>$name</string>
<key>METRICS_BIND</key><string>$address</string>
<key>METRICS_INTERFACE</key><string>$interface</string>
<key>METRICS_ALLOWED_CLIENTS</key><string>10.0.0.161,100.75.169.97,127.0.0.1</string>
</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>5</integer>
<key>StandardErrorPath</key><string>$HOME/Library/Logs/hardware-telemetry.log</string>
</dict></plist>
PLIST
plutil -lint "$plist"
launchctl bootout "gui/$(id -u)/net.luna.hardware-telemetry" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
