#!/bin/bash
#===============================================================================
# lib/services.sh — KaviGuard service status: BlueBubbles + RVG Mac agent
# v1.1.0: adds per-service uptime and restart-count-since-boot tracking.
#===============================================================================

# --- Uptime + restart tracking (state in /tmp, keyed by boot time) ---
_SVC_STATE="/tmp/kavimac-services.state"

_svc_boottime() {
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n kern.boottime 2>/dev/null | awk -F'[=,]' '{print $2}' | tr -d ' ' || echo 0
    else
        echo 0
    fi
}

_svc_pid_by_port() {
    local port="$1"
    command -v lsof >/dev/null 2>&1 || return 1
    lsof -ti ":$port" 2>/dev/null | head -1
}

_svc_uptime() {
    local pid="${1:-}"
    [[ -n "$pid" ]] || { echo "?"; return 0; }
    ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "?"
}

# _svc_restarts <label> <pid> → echoes restarts since boot; updates state file
_svc_restarts() {
    local label="$1" pid="${2:-}"
    local boot restarts old_pid old_boot l p r b
    boot=$(_svc_boottime); restarts=0; old_pid=""; old_boot=""
    if [[ -f "$_SVC_STATE" ]]; then
        while IFS=: read -r l p r b; do
            if [[ "$l" == "$label" ]]; then old_pid="$p"; restarts="$r"; old_boot="$b"; fi
        done < "$_SVC_STATE" 2>/dev/null
    fi
    # New boot (or first run) → counters reset
    if [[ "$old_boot" != "$boot" ]]; then restarts=0; old_pid=""; fi
    # PID changed since last sighting → the service restarted
    if [[ -n "$pid" && -n "$old_pid" && "$pid" != "$old_pid" ]]; then
        restarts=$((restarts + 1))
    fi
    local tmpf="${_SVC_STATE}.tmp"
    : > "$tmpf" 2>/dev/null
    if [[ -f "$_SVC_STATE" ]]; then
        grep -v "^${label}:" "$_SVC_STATE" 2>/dev/null >> "$tmpf" || true
    fi
    echo "${label}:${pid}:${restarts}:${boot}" >> "$tmpf"
    mv "$tmpf" "$_SVC_STATE" 2>/dev/null
    echo "$restarts"
}

# _svc_extra <label> <port> → " | uptime X | restarts since boot: N" (empty if pid unknown)
_svc_extra() {
    local label="$1" port="$2" pid up restarts
    pid=$(_svc_pid_by_port "$port" 2>/dev/null || echo "")
    [[ -n "$pid" ]] || return 0
    up=$(_svc_uptime "$pid")
    restarts=$(_svc_restarts "$label" "$pid")
    echo " | uptime ${up:-?} | restarts since boot: ${restarts:-0}"
}

service_bluebubbles() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:1234/ 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "401" ]]; then
        echo "BlueBubbles: RUNNING (port 1234, http $code)$(_svc_extra bluebubbles 1234)"
    else
        echo "BlueBubbles: DOWN (port 1234 unreachable)"
        echo "  Start it from /Applications or check the LaunchAgent."
    fi
}

service_rvg() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8899/rvd/status 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "401" ]]; then
        echo "RVG Mac agent: RUNNING (port 8899)$(_svc_extra rvd-mac 8899)"
    else
        echo "RVG Mac agent: DOWN (port 8899 unreachable)"
        echo "  Restart: sudo /usr/bin/python3 /opt/rvg-mac/rvg_mac.py &"
    fi
}

service_tailscale() {
    local pid up restarts
    if pgrep -x tailscaled >/dev/null 2>&1 || pgrep -x tailscale >/dev/null 2>&1; then
        local ip
        ip=$(tailscale ip -4 2>/dev/null | head -1)
        pid=$(pgrep -x tailscaled 2>/dev/null | head -1)
        [[ -z "$pid" ]] && pid=$(pgrep -x tailscale 2>/dev/null | head -1)
        up=$(_svc_uptime "$pid")
        restarts=$(_svc_restarts "tailscale" "$pid")
        echo "Tailscale: RUNNING (${ip:-no IP}) | uptime ${up:-?} | restarts since boot: ${restarts:-0}"
    else
        echo "Tailscale: not running"
    fi
}

run_services() {
    echo "=== Service Status ==="
    service_bluebubbles
    service_rvg
    service_tailscale
}
