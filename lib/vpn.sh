#!/bin/bash
#===============================================================================
# lib/vpn.sh — KaviMac KaviVPN management (macOS WireGuard)
#
# Mirrors the Windows design in ~/workspace/seth-vpn/KAVIGUARD_INTEGRATION.md
# but uses macOS-native tooling:
#   - WireGuard via `wg` CLI (brew) or the WireGuard Mac App Store app
#   - Tunnel state via `wg show`
#   - Auto-connect via LaunchAgent (this tool manages its own plist)
#   - Kill switch via pf firewall anchor (full-tunnel mode only)
#
# Config layout (mirrors Windows C:\Tools\KaviVPN\):
#   /opt/kavimac/vpn/
#     kavivpn.conf      # client config (from add-client.sh on the Oracle VM)
#     settings.json     # { TunnelName, AutoConnect, KillSwitchMode, ServerEndpoint }
#
# Status: KaviVPN server is NOT yet deployed (needs Seth's Oracle Cloud VM).
# All functions degrade gracefully to "not configured" until then.
#===============================================================================

VPN_DIR="/opt/kavimac/vpn"
VPN_CONF="$VPN_DIR/kavivpn.conf"
VPN_SETTINGS="$VPN_DIR/settings.json"
WG_IFACE="kavivpn"

_vpn_settings_val() {
    local key="$1" default="$2"
    if [[ -f "$VPN_SETTINGS" ]]; then
        python3 -c "import json;print(json.load(open('$VPN_SETTINGS')).get('$key','$default'))" 2>/dev/null \
            || echo "$default"
    else
        echo "$default"
    fi
}

# --- Is WireGuard available? ---
vpn_installed() {
    command -v wg >/dev/null 2>&1 && return 0
    [[ -d "/Applications/WireGuard.app" ]] && return 0
    return 1
}

# --- Structured status (mirrors Get-KaviVPNStatus) ---
vpn_status() {
    echo "--- KaviVPN Status ---"
    if ! vpn_installed; then
        echo "VPN: WireGuard not installed (brew install wireguard-tools)"
        return 0
    fi
    if [[ ! -f "$VPN_CONF" ]]; then
        echo "VPN: not configured (no client config — deploy KaviVPN server first)"
        return 0
    fi
    local up handshake_age tunnel_ip exit_ip
    if wg show "$WG_IFACE" >/dev/null 2>&1; then
        up=1
        # Latest handshake, epoch seconds
        local hs
        hs=$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null | awk '{print $2}')
        if [[ -n "$hs" && "$hs" != "0" ]]; then
            handshake_age=$(( $(date +%s) - hs ))
        else
            handshake_age="never"
        fi
        tunnel_ip=$(wg show "$WG_IFACE" addresses 2>/dev/null | awk '{print $1}' | head -1)
        # Exit IP through the tunnel (only meaningful in full-tunnel mode)
        exit_ip=$(curl -s --max-time 8 --interface "$WG_IFACE" https://api.ipify.org 2>/dev/null || echo "?")
    else
        up=0
    fi
    local ks ac
    ks=$(_vpn_settings_val "KillSwitchMode" "Off")
    ac=$(_vpn_settings_val "AutoConnect" "false")

    if [[ "$up" == "1" ]]; then
        if [[ "$handshake_age" == "never" ]]; then
            echo "VPN: WARNING — tunnel up, no handshake yet (server or network issue)"
        elif (( handshake_age > 180 )); then
            echo "VPN: WARNING — tunnel up, no handshake for ${handshake_age}s"
        else
            echo "VPN: Connected (handshake ${handshake_age}s ago, tunnel ${tunnel_ip}, exit ${exit_ip})"
        fi
    else
        echo "VPN: Disconnected (torrent-only mode not applicable on Mac — no leak risk when idle)"
    fi
    echo "  Kill switch: $ks | AutoConnect: $ac"
}

# --- Connect: bring the tunnel up ---
vpn_connect() {
    if ! vpn_installed; then echo "ERROR: WireGuard not installed"; return 1; fi
    if [[ ! -f "$VPN_CONF" ]]; then echo "ERROR: no client config at $VPN_CONF"; return 1; fi
    if wg show "$WG_IFACE" >/dev/null 2>&1; then
        echo "KaviVPN already connected."
        return 0
    fi
    sudo wg-quick up "$VPN_CONF" 2>&1 && echo "KaviVPN connected." \
        || { echo "ERROR: wg-quick failed"; return 1; }
}

# --- Disconnect ---
vpn_disconnect() {
    if wg show "$WG_IFACE" >/dev/null 2>&1; then
        sudo wg-quick down "$VPN_CONF" 2>&1 && echo "KaviVPN disconnected." \
            || { echo "ERROR: wg-quick down failed"; return 1; }
    else
        echo "KaviVPN already disconnected."
    fi
}

# --- Auto-connect via LaunchAgent ---
vpn_autoconnect() {
    # usage: vpn_autoconnect on|off|status
    local action="${1:-status}"
    local plist="$HOME/Library/LaunchAgents/com.seth.kavivpn.plist"
    case "$action" in
        on)
            if [[ ! -f "$VPN_CONF" ]]; then echo "ERROR: configure KaviVPN first"; return 1; fi
            cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.seth.kavivpn</string>
    <key>ProgramArguments</key>
    <array><string>/usr/local/bin/wg-quick</string><string>up</string><string>$VPN_CONF</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>NetworkState</key><true/></dict>
</dict>
</plist>
PLIST
            launchctl load "$plist" 2>/dev/null
            _vpn_settings_set "AutoConnect" "true"
            echo "KaviVPN auto-connect enabled."
            ;;
        off)
            launchctl unload "$plist" 2>/dev/null
            rm -f "$plist"
            _vpn_settings_set "AutoConnect" "false"
            echo "KaviVPN auto-connect disabled."
            ;;
        status)
            if [[ -f "$plist" ]]; then echo "AutoConnect: on"; else echo "AutoConnect: off"; fi
            ;;
    esac
}

_vpn_settings_set() {
    local key="$1" val="$2"
    mkdir -p "$VPN_DIR"
    if [[ -f "$VPN_SETTINGS" ]]; then
        python3 - "$VPN_SETTINGS" "$key" "$val" <<'PYEOF' 2>/dev/null
import json, sys
p, k, v = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d[k] = v
json.dump(d, open(p, "w"), indent=2)
PYEOF
    else
        printf '{\n  "TunnelName": "kavivpn",\n  "AutoConnect": "%s",\n  "KillSwitchMode": "Off",\n  "ServerEndpoint": ""\n}\n' \
            "$([[ "$key" == "AutoConnect" ]] && echo "$val" || echo "false")" > "$VPN_SETTINGS"
    fi
}

# --- Kill switch (pf anchor, full-tunnel mode only) ---
# WARNING: arming while disconnected locks the Mac offline. Manual only.
vpn_killswitch() {
    # usage: vpn_killswitch on|off|status
    local action="${1:-status}"
    local anchor="/etc/pf.anchors/com.seth.kavivpn"
    case "$action" in
        on)
            echo "WARNING: kill switch blocks ALL non-VPN traffic."
            echo "Only use in full-tunnel mode. Arming now…"
            sudo sh -c "cat > $anchor" <<'PFEOF'
# KaviVPN kill switch — allow only WireGuard + tunnel + LAN
pass out proto udp to <vpn_server> port 51820
pass on utun0
pass out to 192.168.0.0/16
pass out to 10.0.0.0/8
pass out to 100.64.0.0/10
block out all
PFEOF
            echo "  NOTE: edit $anchor to set your <vpn_server> IP, then:"
            echo "  sudo pfctl -a com.seth.kavivpn -f $anchor && sudo pfctl -e"
            _vpn_settings_set "KillSwitchMode" "On"
            ;;
        off)
            sudo pfctl -a com.seth.kavivpn -F all 2>/dev/null
            _vpn_settings_set "KillSwitchMode" "Off"
            echo "KaviVPN kill switch disabled."
            ;;
        status)
            _vpn_settings_val "KillSwitchMode" "Off" | sed 's/^/Kill switch: /'
            ;;
    esac
}

# --- One-line report for health checks ---
vpn_report() {
    if ! vpn_installed; then echo "VPN: not installed"; return; fi
    if [[ ! -f "$VPN_CONF" ]]; then echo "VPN: not configured"; return; fi
    local hs age
    if wg show "$WG_IFACE" >/dev/null 2>&1; then
        hs=$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null | awk '{print $2}')
        if [[ -n "$hs" && "$hs" != "0" ]]; then
            age=$(( $(date +%s) - hs ))
            (( age < 180 )) && echo "VPN: Connected (handshake ${age}s ago)" \
                             || echo "VPN: WARNING — no handshake for ${age}s"
        else
            echo "VPN: tunnel up, no handshake yet"
        fi
    else
        echo "VPN: Disconnected"
    fi
}
