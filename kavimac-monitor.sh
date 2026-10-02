#!/bin/bash
#===============================================================================
# kavimac-monitor.sh — KaviMac background health monitor
# Runs via LaunchAgent (com.seth.kavimac.plist), logs to /tmp/kavimac-monitor.log
# Checks: services (BlueBubbles, RVG, Tailscale), disk space, memory pressure.
# Alerts via macOS notification when something is wrong.
#===============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/tmp/kavimac-monitor.log"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/services.sh"
source "$SCRIPT_DIR/lib/vpn.sh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

notify() {
    local title="$1" msg="$2"
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null
    log "NOTIFY: $title — $msg"
}

log "--- monitor run ---"

# 1. BlueBubbles must be up (Seth's iMessage bridge)
if ! curl -s -o /dev/null --max-time 5 http://localhost:1234/ 2>/dev/null; then
    notify "KaviMac" "BlueBubbles is DOWN (port 1234)"
else
    log "BlueBubbles: ok"
fi

# 2. RVG Mac agent must be up
if ! curl -s -o /dev/null --max-time 5 http://localhost:8899/rvd/status 2>/dev/null; then
    notify "KaviMac" "RVG Mac agent is DOWN (port 8899)"
else
    log "RVG: ok"
fi

# 3. Disk space warning at 90%
disk_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
if [[ -n "$disk_pct" ]] && (( disk_pct >= 90 )); then
    notify "KaviMac" "Disk ${disk_pct}% full — run kavimac.sh --cleanup"
fi
log "disk: ${disk_pct}%"

# 4. Heavy swap warning (>2GB on 8GB machine)
swap_mb=$(sysctl -n vm.swapusage 2>/dev/null | awk -F'[=,M]' '{print $3}' | tr -d ' ' | cut -d. -f1)
if [[ -n "$swap_mb" ]] && (( swap_mb > 2048 )); then
    notify "KaviMac" "Heavy swap usage (${swap_mb}MB) — memory pressure high"
fi
log "swap: ${swap_mb}MB"

# 5. KaviVPN auto-reconnect (only if AutoConnect is on)
if [[ -f /opt/kavimac/vpn/settings.json ]]; then
    ac=$(python3 -c "import json;print(json.load(open('/opt/kavimac/vpn/settings.json')).get('AutoConnect','false'))" 2>/dev/null)
    if [[ "$ac" == "true" ]] && command -v wg >/dev/null 2>&1; then
        if ! wg show kavivpn >/dev/null 2>&1; then
            log "KaviVPN auto-reconnect…"
            sudo wg-quick up /opt/kavimac/vpn/kavivpn.conf 2>/dev/null \
                && log "KaviVPN reconnected" \
                || notify "KaviMac" "KaviVPN auto-reconnect FAILED"
        fi
    fi
fi

log "--- monitor done ---"
