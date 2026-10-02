#!/bin/bash
#===============================================================================
# KaviGuard — macOS tune-up & optimization for Seth's M1 MacBook Air
# Version 1.1.0 "Server Guard" | Native Apple Silicon (no Rosetta)
#
# Usage:
#   ./kavimac.sh                    full run (guardrail check + cleanup preview
#                                   + optimize + health + services)
#   ./kavimac.sh --cleanup [--yes]  safe junk sweep (preview by default)
#   ./kavimac.sh --uninstall <App>  complete uninstall + leftovers
#   ./kavimac.sh --find-orphans     leftover scan for long-removed apps
#   ./kavimac.sh --disk [path]      size-sorted disk browser
#   ./kavimac.sh --snapshots        APFS local snapshots + purgeable space
#   ./kavimac.sh --startup          login items + launchd manager
#   ./kavimac.sh --prune-languages  conservative language prune (opt-in)
#   ./kavimac.sh --maintenance      on-demand periodic scripts + DB rebuilds
#   ./kavimac.sh --power            power baseline verify (never-sleep check)
#   ./kavimac.sh --fix-power        re-apply known-good power baseline
#   ./kavimac.sh --guard            protected-services guardrail check
#   ./kavimac.sh --health           health check only
#   ./kavimac.sh --services         service status only
#   ./kavimac.sh --optimize         optimization report only
#   ./kavimac.sh --vpn-status       KaviVPN status only
#
# Philosophy (from KaviGuard): report first, clean safely, optimize sensibly.
# v1.1.0 "Server Guard": every destructive action runs through the protected-
# services whitelist (BlueBubbles, rvd-mac, Tailscale, KaviGuard) and goes to
# Trash first — nothing is deleted without a restore path.
#===============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "1.1.0")

# Source order matters: common first (shared helpers), guard second (safety).
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/guard.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/cleanup.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/health.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/optimize.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/vpn.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/services.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/power.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/uninstall.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/disk.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/startup.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/languages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/maintenance.sh"

banner() {
    echo "===================================================="
    echo "  KaviGuard v$VERSION \"Server Guard\" — tune-up for Seths-MacBook-Air"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "===================================================="
    echo ""
}

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \?//'
    exit 1
}

# --- Full run: guardrail check first, then the standard sweep ---
run_full() {
    echo "=== KaviGuard Full Run ==="
    echo ""
    echo "--- Guardrail check ---"
    if ! guard_check; then
        echo ""
        echo "  WARNING: a protected service is down — continuing with safe checks only."
        echo "  Run ./kavimac.sh --services for detail."
    fi
    echo ""; echo ""
    run_cleanup;  echo ""; echo ""
    run_optimize; echo ""; echo ""
    run_health;   echo ""; echo ""
    run_services; echo ""
    vpn_report
    echo ""
    echo "--- Power baseline ---"
    power_verify
}

# --- Argument parsing (supports --cleanup --yes, --uninstall <App>, --disk [path]) ---
mode="--full"
mode_arg=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) KAVIMAC_YES=1; shift ;;
        --full|--cleanup|--find-orphans|--snapshots|--startup|--prune-languages|\
        --maintenance|--fix-power|--power|--guard|--health|--services|--optimize|--vpn-status)
            mode="$1"; shift ;;
        --uninstall)
            mode="$1"; mode_arg="${2:-}"; shift 2 ;;
        --disk)
            mode="$1"
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then mode_arg="$2"; shift 2; else shift; fi ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

banner
case "$mode" in
    --full)           run_full ;;
    --cleanup)        run_cleanup ;;
    --uninstall)
        [[ -z "$mode_arg" ]] && { echo "Usage: $0 --uninstall <App Name>"; exit 1; }
        uninstall_app "$mode_arg" ;;
    --find-orphans)   find_orphans ;;
    --disk)           disk_browser ${mode_arg:+"$mode_arg"} ;;
    --snapshots)      run_snapshots ;;
    --startup)        startup_list ;;
    --prune-languages) prune_languages ;;
    --maintenance)    run_maintenance ;;
    --power)          power_verify ;;
    --fix-power)      power_fix ;;
    --guard)          guard_check ;;
    --health)         run_health ;;
    --services)       run_services ;;
    --optimize)       run_optimize ;;
    --vpn-status)     vpn_status ;;
    *) usage ;;
esac

echo ""
echo "Done. KaviGuard v$VERSION"
