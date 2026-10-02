#!/bin/bash
#===============================================================================
# lib/cleanup.sh — KaviMac cleanup functions
# Safe system cleanup: caches, logs, trash. Reports space freed.
# Never touches user documents, photos, music, or app data.
#===============================================================================

# Get directory size in bytes (0 if missing)
_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sk "$dir" 2>/dev/null | awk '{print $1 * 1024}'
    else
        echo 0
    fi
}

# Format bytes as human-readable
_fmt_bytes() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# --- User caches (safe: apps rebuild them) ---
cleanup_user_caches() {
    local before after freed
    before=$(_dir_size "$HOME/Library/Caches")
    # Remove contents but keep the directory structure intact
    find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 \
        ! -name "com.apple.Safari" \
        ! -name "com.apple.finder" \
        -exec rm -rf {} + 2>/dev/null
    after=$(_dir_size "$HOME/Library/Caches")
    freed=$((before - after))
    echo "USER_CACHES_FREED=$freed"
    echo "  User caches: freed $(_fmt_bytes $freed)"
}

# --- System caches (needs sudo; safe subset only) ---
cleanup_system_caches() {
    if [[ $EUID -ne 0 ]]; then
        echo "  System caches: skipped (needs sudo)"
        echo "SYSTEM_CACHES_FREED=0"
        return 0
    fi
    local before after freed
    before=$(_dir_size "/Library/Caches")
    # Only remove clearly safe temp caches, never kernel or driver caches
    find /Library/Caches -mindepth 1 -maxdepth 1 -name "com.apple.*" \
        -exec rm -rf {} + 2>/dev/null
    after=$(_dir_size "/Library/Caches")
    freed=$((before - after))
    echo "SYSTEM_CACHES_FREED=$freed"
    echo "  System caches: freed $(_fmt_bytes $freed)"
}

# --- Trash ---
cleanup_trash() {
    local before after freed
    before=$(_dir_size "$HOME/.Trash")
    rm -rf "$HOME/.Trash/"* 2>/dev/null
    # Also other volumes' trashes for this user
    for vol in /Volumes/*/.Trashes/$UID; do
        [[ -d "$vol" ]] && rm -rf "$vol/"* 2>/dev/null
    done
    after=$(_dir_size "$HOME/.Trash")
    freed=$((before - after))
    echo "TRASH_FREED=$freed"
    echo "  Trash: freed $(_fmt_bytes $freed)"
}

# --- Old logs (keep last 7 days) ---
cleanup_logs() {
    local freed=0
    # User logs older than 7 days
    if [[ -d "$HOME/Library/Logs" ]]; then
        local b a
        b=$(_dir_size "$HOME/Library/Logs")
        find "$HOME/Library/Logs" -type f -mtime +7 -delete 2>/dev/null
        a=$(_dir_size "$HOME/Library/Logs")
        freed=$((freed + b - a))
    fi
    # System logs need sudo
    if [[ $EUID -eq 0 ]]; then
        local b a
        b=$(_dir_size "/var/log")
        find /var/log -type f -name "*.log.*" -mtime +7 -delete 2>/dev/null
        find /var/log -type f -name "*.gz" -mtime +7 -delete 2>/dev/null
        a=$(_dir_size "/var/log")
        freed=$((freed + b - a))
    fi
    echo "LOGS_FREED=$freed"
    echo "  Old logs: freed $(_fmt_bytes $freed)"
}

# --- DNS cache ---
cleanup_dns_cache() {
    dscacheutil -flushcache 2>/dev/null
    killall -HUP mDNSResponder 2>/dev/null
    echo "  DNS cache: flushed"
    echo "DNS_FLUSHED=1"
}

# --- Xcode derived data (dev junk, often GBs) ---
cleanup_xcode_derived() {
    local dd="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ -d "$dd" ]]; then
        local before after freed
        before=$(_dir_size "$dd")
        rm -rf "$dd/"* 2>/dev/null
        after=$(_dir_size "$dd")
        freed=$((before - after))
        echo "XCODE_FREED=$freed"
        echo "  Xcode DerivedData: freed $(_fmt_bytes $freed)"
    else
        echo "XCODE_FREED=0"
    fi
}

# --- Run all cleanup, return total freed ---
run_cleanup() {
    echo "=== KaviMac Cleanup ==="
    local total=0 line val
    while IFS= read -r line; do
        echo "$line"
        if [[ "$line" =~ ^[A-Z_]+_FREED=([0-9]+)$ ]]; then
            val="${BASH_REMATCH[1]}"
            total=$((total + val))
        fi
    done < <(
        cleanup_user_caches
        cleanup_system_caches
        cleanup_trash
        cleanup_logs
        cleanup_dns_cache
        cleanup_xcode_derived
    )
    echo ""
    echo "TOTAL_FREED=$total"
    echo "Total freed: $(_fmt_bytes $total)"
}
