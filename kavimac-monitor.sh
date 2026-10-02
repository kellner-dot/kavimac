#!/bin/bash
#===============================================================================
# kavimac-monitor.sh — KaviGuard background health monitor
# Runs via LaunchAgent (com.seth.kavimac.plist), logs to /tmp/kavimac-monitor.log
# Checks: services (BlueBubbles, RVG, Tailscale), lid-close guard, disk space
# (incl. purgeable), memory pressure.
# Alerts via macOS notification when something is wrong.
# v1.1.0: BlueBubbles auto-restart (max 2 tries per outage, then notify only).
#===============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/tmp/kavimac-monitor.log"
BB_STATE="/tmp/kavimac-bb-restart.state"
TS_STATE="/tmp/kavimac-ts-restart.state"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/power.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/services.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/vpn.sh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

notify() {
    local title="$1" msg="$2"
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null
    log "NOTIFY: $title — $msg"
}

_bb_up() {
    curl -s -o /dev/null --max-time 5 http://localhost:1234/ 2>/dev/null
}

# BlueBubbles auto-restart: up to 2 attempts per outage, then notify only.
# The counter resets the moment the service is healthy again — never a loop.
bb_autorestart() {
    if _bb_up; then
        echo 0 > "$BB_STATE" 2>/dev/null
        log "BlueBubbles: ok"
        return 0
    fi
    local tries
    tries=$(cat "$BB_STATE" 2>/dev/null || echo 0)
    [[ "$tries" =~ ^[0-9]+$ ]] || tries=0
    if (( tries < 2 )); then
        log "BlueBubbles DOWN — restart attempt $((tries + 1))/2"
        local uid
        uid=$(id -u 2>/dev/null || echo 501)
        launchctl kickstart "gui/$uid/com.bluebubbles.blububbles-server" 2>/dev/null \
        || launchctl kickstart "gui/$uid/com.bluebubbles.server" 2>/dev/null \
        || open -a BlueBubbles 2>/dev/null
        sleep 8
        if _bb_up; then
            echo 0 > "$BB_STATE" 2>/dev/null
            notify "KaviGuard" "BlueBubbles recovered after restart"
        else
            echo $((tries + 1)) > "$BB_STATE" 2>/dev/null
            notify "KaviGuard" "BlueBubbles is DOWN — restart attempt $((tries + 1)) failed"
        fi
    else
        notify "KaviGuard" "BlueBubbles is DOWN (restart attempts exhausted — needs a manual check)"
    fi
    return 1
}

log "--- monitor run ---"

# 1. BlueBubbles must be up (Seth's iMessage bridge) — auto-restart, max 2 tries
bb_autorestart || true

# 1b. Tailscale must be up (Seth's tailnet) — auto-restart, max 2 tries
# ROOT CAUSE (v1.1.3): Tailscale.app is a GUI app with no keep-alive. When it
# dies (crash, logout, system hiccup), nothing restarts it. The monitor now
# tries `open -a Tailscale` up to 2x per outage, then notifies Seth that manual
# login may be needed (the most common reason the daemon exits immediately is
# a missing/invalid Tailscale account login).
ts_autorestart() {
    if pgrep -x tailscaled >/dev/null 2>&1 || pgrep -x tailscale >/dev/null 2>&1; then
        echo 0 > "$TS_STATE" 2>/dev/null
        log "Tailscale: ok"
        return 0
    fi
    local tries
    tries=$(cat "$TS_STATE" 2>/dev/null || echo 0)
    [[ "$tries" =~ ^[0-9]+$ ]] || tries=0
    if (( tries < 2 )); then
        log "Tailscale DOWN — restart attempt $((tries + 1))/2"
        # Try the GUI app first (handles login state), fall back to CLI
        open -a Tailscale 2>/dev/null
        sleep 10
        if pgrep -x tailscaled >/dev/null 2>&1 || pgrep -x tailscale >/dev/null 2>&1; then
            echo 0 > "$TS_STATE" 2>/dev/null
            notify "KaviGuard" "Tailscale recovered after restart"
            log "Tailscale: recovered"
        else
            echo $((tries + 1)) > "$TS_STATE" 2>/dev/null
            # Check if the app exists but won't stay up (likely needs login)
            if [[ -d "/Applications/Tailscale.app" ]]; then
                notify "KaviGuard" "Tailscale is DOWN — restart attempt $((tries + 1)) failed. May need manual login in Tailscale.app"
            else
                notify "KaviGuard" "Tailscale is DOWN — Tailscale.app not found in /Applications"
            fi
        fi
    else
        # Don't spam — only notify once per outage (state file already at 2)
        log "Tailscale still DOWN (restart attempts exhausted)"
    fi
    return 1
}
ts_autorestart || true

# 2. RVG Mac agent must be up
if ! curl -s -o /dev/null --max-time 5 http://localhost:8899/rvd/status 2>/dev/null; then
    notify "KaviGuard" "RVG Mac agent is DOWN (port 8899)"
else
    log "RVG: ok"
fi

# 2b. Lid-close guard must be alive — a sleeping laptop is not a server
if lidguard_check >/dev/null 2>&1; then
    log "lidguard: ok"
else
    notify "KaviGuard" "Lid-close guard MISSING — the server is a sleeping laptop right now"
fi

# 3. Disk space warning at 90% (with purgeable-space context)
disk_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
purgeable=$(diskutil info / 2>/dev/null | grep -i "purgeable" | head -1 | sed 's/^ *//')
[[ -n "$purgeable" ]] && log "purgeable: $purgeable"
if [[ -n "$disk_pct" ]] && (( disk_pct >= 90 )); then
    if [[ -n "$purgeable" ]]; then
        notify "KaviGuard" "Disk ${disk_pct}% full ($purgeable) — run kavimac.sh --snapshots"
    else
        notify "KaviGuard" "Disk ${disk_pct}% full — run kavimac.sh --cleanup"
    fi
fi
log "disk: ${disk_pct}%"

# 4. Heavy swap warning (>2GB on 8GB machine)
# NOTE (v1.1.0 fix): the old awk -F'[=,M]' '{print $3}' parsing grabbed the
# literal word "used" instead of the number, which crashed the monitor under
# set -u ("unbound variable"). Parse the numeric MB after "used =" instead.
swap_mb=$(sysctl -n vm.swapusage 2>/dev/null | sed -n 's/.*used = \([0-9][0-9.]*\)M.*/\1/p' | cut -d. -f1)
[[ "$swap_mb" =~ ^[0-9]+$ ]] || swap_mb=""
if [[ -n "$swap_mb" ]] && (( swap_mb > 2048 )); then
    notify "KaviGuard" "Heavy swap usage (${swap_mb}MB) — memory pressure high"
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
                || notify "KaviGuard" "KaviVPN auto-reconnect FAILED"
        fi
    fi
fi

log "--- monitor done ---"
