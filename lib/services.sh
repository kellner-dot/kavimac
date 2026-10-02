#!/bin/bash
#===============================================================================
# lib/services.sh — KaviMac service status: BlueBubbles + RVG Mac agent
#===============================================================================

service_bluebubbles() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:1234/ 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "401" ]]; then
        echo "BlueBubbles: RUNNING (port 1234, http $code)"
    else
        echo "BlueBubbles: DOWN (port 1234 unreachable)"
        echo "  Start it from /Applications or check the LaunchAgent."
    fi
}

service_rvg() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8899/rvd/status 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "401" ]]; then
        echo "RVG Mac agent: RUNNING (port 8899, v1.0.0)"
    else
        echo "RVG Mac agent: DOWN (port 8899 unreachable)"
        echo "  Restart: sudo /usr/bin/python3 /opt/rvg-mac/rvg_mac.py &"
    fi
}

service_tailscale() {
    if pgrep -x tailscaled >/dev/null 2>&1 || pgrep -x tailscale >/dev/null 2>&1; then
        local ip
        ip=$(tailscale ip -4 2>/dev/null | head -1)
        echo "Tailscale: RUNNING (${ip:-no IP})"
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
