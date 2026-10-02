#!/bin/bash
#===============================================================================
# lib/disk.sh — KaviMac disk space visualizer + APFS snapshot manager
# Read-only disk browser and local-snapshot lister. The only destructive step
# is snapshots_thin, which thins Time Machine local snapshots and always
# asks first. Never touches /System.
#===============================================================================

#--- Size-sorted directory browser ------------------------------------------------

disk_browser() {
    local path="${1:-$HOME}"
    # Normalize: strip trailing slash (keep root as "/")
    [[ "$path" != "/" ]] && path="${path%/}"
    # Never touch /System
    if [[ "$path" == "/System" || "$path" == "/System/"* ]]; then
        echo "REFUSED: /System is off-limits"
        return 1
    fi
    if [[ ! -d "$path" ]]; then
        echo "Not a directory: $path"
        return 1
    fi
    if ! command -v du >/dev/null 2>&1; then
        echo "du is not available — cannot browse disk usage"
        return 1
    fi

    echo "DISK_BROWSER_PATH=$path"
    echo "Top 25 entries by size under: $path"
    # du -sm (MB); fallback to -sk (KB) if -m unsupported
    if du -sm "$path" >/dev/null 2>&1; then
        du -sm -- "$path"/* 2>/dev/null | sort -rn | head -25 \
            | awk '{printf "%6d MB  %s\n", $1, substr($0, index($0,$2))}'
    else
        du -sk -- "$path"/* 2>/dev/null | sort -rn | head -25 \
            | awk '{printf "%9.1f MB  %s\n", $1/1024, substr($0, index($0,$2))}'
    fi
    echo "For a visual map, try Radix or GrandPerspective (both free)."
}

#--- APFS local snapshots + purgeable space --------------------------------------

snapshots_list() {
    local count=0
    echo "=== APFS local snapshots (/) ==="
    if ! command -v tmutil >/dev/null 2>&1; then
        echo "tmutil not available — cannot list snapshots"
    else
        local snap_out snap
        snap_out=$(tmutil listlocalsnapshots / 2>&1) || true
        snap=$(echo "$snap_out" | grep -E "^com\.apple\.TimeMachine" || true)
        if [[ -z "$snap" ]]; then
            echo "No local snapshots found."
        else
            echo "$snap"
            count=$(echo "$snap" | wc -l | tr -d ' ')
        fi
    fi
    echo "SNAPSHOT_COUNT=$count"
    echo ""
    echo "=== Purgeable space (/) ==="
    local purgeable="unknown"
    if command -v diskutil >/dev/null 2>&1; then
        local pi
        pi=$(diskutil info / 2>/dev/null | grep -i purgeable | head -1) || true
        if [[ -z "$pi" ]]; then
            # Fallback: diskutil apfs list "Purgeable" line
            pi=$(diskutil apfs list 2>/dev/null | grep -i purgeable | head -1) || true
        fi
        if [[ -n "$pi" ]]; then
            purgeable=$(echo "$pi" | awk -F': *' '{print $2}' | sed 's/^[[:space:]]*//')
            [[ -z "$purgeable" ]] && purgeable="$pi"
        else
            purgeable="not reported"
        fi
    else
        purgeable="diskutil not available"
    fi
    echo "Purgeable: $purgeable"
    echo "PURGEABLE=$purgeable"
}

snapshots_thin() {
    snapshots_list
    echo ""
    if ! command -v tmutil >/dev/null 2>&1; then
        echo "tmutil not available — cannot thin snapshots"
        echo "SNAPSHOTS_THINNED=0"
        return 1
    fi
    if ! confirm "Thin APFS local snapshots to reclaim purgeable space?"; then
        echo "SNAPSHOTS_THINNED=0"
        klog "snapshot thin cancelled by user"
        return 0
    fi
    # 10 GB target, urgency 100. May require sudo on some macOS versions.
    local thinned=0
    if tmutil thinlocalsnapshots / $((10*1024*1024*1024)) 100 2>&1; then
        thinned=1
        echo "Snapshots thinned."
        klog "thinned APFS local snapshots (10 GB target, urgency 100)"
    else
        echo "tmutil thinlocalsnapshots failed — try running it with sudo:"
        echo "  sudo tmutil thinlocalsnapshots / $((10*1024*1024*1024)) 100"
        klog "snapshot thin failed without sudo; advised sudo command"
    fi
    echo "SNAPSHOTS_THINNED=$thinned"
}

run_snapshots() {
    echo "=== KaviMac Snapshot Report ==="
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    snapshots_list
}
