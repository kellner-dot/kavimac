#!/bin/bash
#===============================================================================
# lib/guard.sh — KaviGuard Server Guard: protected-services whitelist
# The always-on services on this Mac (BlueBubbles, rvd-mac, Tailscale, KaviGuard
# monitor) are load-bearing. Every other module must call guard_require before
# any destructive action; guard_check verifies the whitelist is alive.
# Philosophy: the server keeps running even if the tune-up goes wrong.
#===============================================================================
#
# Sourced after lib/common.sh; uses its helpers (klog).

# Never stop, disable, kill, or uninstall anything matching one of these
# (case-insensitive substring match).
GUARD_WHITELIST=("BlueBubbles" "rvd-mac" "RVD" "Tailscale" "tailscale" "KaviGuard" "kavimac")

# guard_is_protected <name> — return 0 if <name> matches the whitelist, else 1
guard_is_protected() {
    local name=${1:-}
    [[ -n "$name" ]] || return 1
    local lower_name lower_entry entry
    lower_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    for entry in "${GUARD_WHITELIST[@]}"; do
        lower_entry=$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')
        case "$lower_name" in
            *"$lower_entry"*) return 0 ;;
        esac
    done
    return 1
}

# guard_require <name> — gate for destructive actions.
# Refuses (stderr + return 1) when <name> is protected; returns 0 otherwise.
guard_require() {
    local name=${1:-}
    if guard_is_protected "$name"; then
        echo "BLOCKED: '$name' is a protected service — not touching it." >&2
        klog "guard BLOCKED action on protected service '$name'"
        return 1
    fi
    return 0
}

# guard_check — verify every protected service is alive.
# Prints one RUNNING/DOWN line per service plus GUARD_OK=1/0.
# Returns 0 only when everything is up.
guard_check() {
    local all_up=1
    local code

    # BlueBubbles (port 1234) and rvd-mac (port 8899) — curl reachability
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            http://localhost:1234/ 2>/dev/null)
        if [[ "$code" == "200" || "$code" == "401" ]]; then
            echo "BlueBubbles: RUNNING (port 1234)"
        else
            echo "BlueBubbles: DOWN (port 1234 unreachable)"
            all_up=0
        fi
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            http://localhost:8899/rvd/status 2>/dev/null)
        if [[ "$code" == "200" || "$code" == "401" ]]; then
            echo "rvd-mac: RUNNING (port 8899)"
        else
            echo "rvd-mac: DOWN (port 8899 unreachable)"
            all_up=0
        fi
    else
        echo "BlueBubbles: UNKNOWN (curl missing)"
        echo "rvd-mac: UNKNOWN (curl missing)"
        all_up=0
    fi

    # Tailscale — daemon process
    if command -v pgrep >/dev/null 2>&1 && \
       { pgrep -x tailscaled >/dev/null 2>&1 || pgrep -x tailscale >/dev/null 2>&1; }; then
        echo "Tailscale: RUNNING"
    else
        echo "Tailscale: DOWN"
        all_up=0
    fi

    # KaviGuard monitor — LaunchAgent com.seth.kaviguard, fallback to process match
    local mon_up=0
    if command -v launchctl >/dev/null 2>&1 && \
       launchctl list com.seth.kaviguard >/dev/null 2>&1; then
        mon_up=1
    elif command -v pgrep >/dev/null 2>&1 && \
         pgrep -f kavimac-monitor >/dev/null 2>&1; then
        mon_up=1
    fi
    if (( mon_up )); then
        echo "KaviGuard monitor: RUNNING"
    else
        echo "KaviGuard monitor: DOWN"
        all_up=0
    fi

    if (( all_up )); then
        echo "GUARD_OK=1"
        klog "guard_check: all protected services RUNNING"
        return 0
    fi
    echo "GUARD_OK=0"
    klog "guard_check: one or more protected services DOWN"
    return 1
}
