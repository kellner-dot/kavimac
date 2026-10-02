#!/bin/bash
#===============================================================================
# lib/optimize.sh — KaviMac performance optimization (report + safe tweaks)
# Philosophy: report first, only apply safe reversible changes.
#===============================================================================

opt_login_items() {
    echo "--- Login Items ---"
    # Modern macOS: sfltool
    local items
    items=$(sfltool dumpbtm 2>/dev/null | grep -A2 "Login Item" | head -20)
    if [[ -n "$items" ]]; then
        echo "$items" | head -15
    else
        # Fallback: check LaunchAgents
        local count
        count=$(ls ~/Library/LaunchAgents/*.plist 2>/dev/null | wc -l | tr -d ' ')
        echo "  $count user LaunchAgents"
        ls ~/Library/LaunchAgents/ 2>/dev/null | sed 's/^/    /'
    fi
    echo "  (Report only — remove manually in System Settings > General > Login Items)"
}

opt_spotlight() {
    echo "--- Spotlight ---"
    local status
    status=$(mdutil -s / 2>/dev/null | head -1)
    echo "  $status"
    if echo "$status" | grep -qi "indexing"; then
        echo "  NOTE: Spotlight is indexing — system may feel slow until done"
    fi
}

opt_filevault() {
    echo "--- FileVault ---"
    local fv
    fv=$(fdesetup status 2>/dev/null)
    echo "  $fv"
}

opt_updates() {
    echo "--- Software Updates ---"
    # Quick check without downloading the full catalog (fast)
    local upd
    upd=$(softwareupdate -l 2>&1 | grep -E "^\*|Title:" | head -5)
    if [[ -n "$upd" ]]; then
        echo "$upd" | sed 's/^/  /'
    else
        echo "  No updates pending (or check requires admin)"
    fi
}

opt_memory_pressure() {
    echo "--- Memory ---"
    # M1 with 8GB: flag if swap is heavy
    # NOTE (v1.1.0 fix): the old awk -F'[=,M]' '{print $3}' parsing grabbed the
    # literal word "used" instead of the number, crashing under set -u.
    local swap_used
    swap_used=$(sysctl -n vm.swapusage 2>/dev/null | sed -n 's/.*used = \([0-9][0-9.]*\)M.*/\1/p' | cut -d. -f1)
    [[ "$swap_used" =~ ^[0-9]+$ ]] || swap_used=""
    echo "  Swap used: ${swap_used:-?} MB"
    if [[ -n "$swap_used" ]] && (( swap_used > 2048 )); then
        echo "  WARNING: heavy swap usage (>2GB) — 8GB RAM is under pressure."
        echo "  Consider closing browser tabs / heavy apps."
    fi
}

opt_server_tweaks() {
    # Safe, reversible server-mode tweaks (idempotent)
    echo "--- Server Tweaks ---"
    # 1. Ensure sleep is off (Seth already set this; verify)
    local sleep_c sleep_b
    sleep_c=$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f&&/sleep/{print $2; exit}')
    if [[ "$sleep_c" != "0" ]]; then
        echo "  NOTE: AC sleep is not 0 — run: sudo pmset -c sleep 0"
    else
        echo "  [ok] AC sleep disabled"
    fi
    # 2. Wake for network access (lets tailnet/WoL wake the Mac)
    local womp
    womp=$(pmset -g 2>/dev/null | awk '/womp/{print $2}')
    [[ "$womp" == "1" ]] && echo "  [ok] Wake for network access on" \
        || echo "  NOTE: womp off — run: sudo pmset -c womp 1"
    # 3. Disable sudden motion sensor (irrelevant on SSD, harmless)
    # 4. Reduce transparency (GPU/compositor win on M1, reversible in Settings)
    local reduce_transparency
    reduce_transparency=$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null)
    if [[ "$reduce_transparency" == "1" ]]; then
        echo "  [ok] Reduce transparency on"
    else
        echo "  TIP: System Settings > Accessibility > Display > Reduce transparency (saves GPU)"
    fi
}

run_optimize() {
    echo "=== KaviMac Optimization ==="
    opt_login_items;      echo ""
    opt_spotlight;        echo ""
    opt_filevault;        echo ""
    opt_updates;          echo ""
    opt_memory_pressure;  echo ""
    opt_server_tweaks
}
