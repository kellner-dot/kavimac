#!/bin/bash
#===============================================================================
# KaviMac — macOS tune-up & optimization for Seth's M1 MacBook Air
# Version 1.0.0 | Native Apple Silicon (no Rosetta)
#
# Usage:
#   ./kavimac.sh              full tune-up (cleanup + optimize + health)
#   ./kavimac.sh --cleanup    cleanup only
#   ./kavimac.sh --optimize   optimization report only
#   ./kavimac.sh --health     health check only
#   ./kavimac.sh --services   service status only
#   ./kavimac.sh --vpn-status KaviVPN status only
#
# Philosophy (from KaviGuard): report first, clean safely, optimize sensibly.
# Nothing destructive runs without being listed here.
#===============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "1.0.0")

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/cleanup.sh"
source "$SCRIPT_DIR/lib/health.sh"
source "$SCRIPT_DIR/lib/optimize.sh"
source "$SCRIPT_DIR/lib/vpn.sh"
source "$SCRIPT_DIR/lib/services.sh"

banner() {
    echo "===================================================="
    echo "  KaviMac v$VERSION — tune-up for Seths-MacBook-Air"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "===================================================="
    echo ""
}

usage() {
    echo "Usage: $0 [--cleanup|--optimize|--health|--services|--vpn-status|--full]"
    exit 1
}

mode="${1:---full}"

banner
case "$mode" in
    --cleanup)   run_cleanup ;;
    --optimize)  run_optimize ;;
    --health)    run_health ;;
    --services)  run_services ;;
    --vpn-status) vpn_status ;;
    --full)
        run_cleanup;  echo ""; echo ""
        run_optimize; echo ""; echo ""
        run_health;   echo ""; echo ""
        run_services; echo ""
        vpn_report
        ;;
    *) usage ;;
esac

echo ""
echo "Done. KaviMac v$VERSION"
