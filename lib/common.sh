#!/bin/bash
#===============================================================================
# lib/common.sh — KaviGuard shared helpers
# Sized reads, human byte formatting, logging, trash-first deletion, prompts.
# Philosophy: reversible first — nothing disappears without a restore path.
#===============================================================================
#
# Sourced by the parent script before any other lib file; guard.sh and all
# other modules call these helpers directly.

# Get directory size in bytes (0 if missing or du unavailable)
_dir_size() {
    local dir=${1:-}
    local size
    if [[ -n "$dir" && -d "$dir" ]] && command -v du >/dev/null 2>&1; then
        size=$(du -sk "$dir" 2>/dev/null | awk '{print $1 * 1024}')
        echo "${size:-0}"
    else
        echo 0
    fi
}

# Format bytes as human-readable (1 decimal: GB/MB/KB, integer B)
_fmt_bytes() {
    local bytes=${1:-0}
    if command -v awk >/dev/null 2>&1; then
        awk -v b="$bytes" 'BEGIN {
            if (b >= 1073741824) printf "%.1f GB", b / 1073741824;
            else if (b >= 1048576) printf "%.1f MB", b / 1048576;
            else if (b >= 1024) printf "%.1f KB", b / 1024;
            else printf "%d B", b;
        }'
    else
        echo "${bytes} B"
    fi
}

# Append "[YYYY-MM-DD HH:MM:SS] <msg>" to the KaviGuard log
klog() {
    local msg=${1:-}
    local logdir="$HOME/Library/Logs"
    mkdir -p "$logdir" 2>/dev/null || true
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" \
        >> "$logdir/kavimac.log" 2>/dev/null || true
    return 0
}

# True when deletions should bypass the Trash and use rm -rf directly.
# Default: yes when running as root (EUID 0). Finder-based trash pops a GUI
# password dialog per protected item even under sudo, which defeats the
# single sudo auth at launch. Normal users keep trash-first reversibility.
# Override: KAVIGUARD_RM_MODE=rm forces direct rm; =trash forces Trash.
_use_direct_rm() {
    case "${KAVIGUARD_RM_MODE:-}" in
        rm)    return 0 ;;
        trash) return 1 ;;
    esac
    [ "${EUID:-$(id -u 2>/dev/null || echo 1)}" -eq 0 ]
}

# Move each existing path to the user's Trash instead of deleting it.
# Tries Finder (keeps "Put Back" working), falls back to mv into
# ~/.Trash/<basename>.<epoch>. Emits TRASHED=<path> per item and TRASHED_COUNT.
# When running as root (sudo), deletes directly with rm -rf instead — Finder
# trash would pop a GUI password dialog per protected item even with sudo
# rights. Emits DELETED=<path> per item and DELETED_COUNT in that mode.
# Always returns 0 — a failed delete must never abort a run.
trash_first() {
    local count=0
    local path base dest esc
    if _use_direct_rm; then
        for path in "$@"; do
            [[ -e "$path" || -L "$path" ]] || continue
            # Safety: never rm an empty path or /.
            [[ -n "$path" && "$path" != "/" ]] || continue
            if rm -rf -- "$path" 2>/dev/null; then
                klog "deleted as root '$path' (direct rm — sudo run, no Trash)"
                echo "DELETED=$path"
                echo "  Deleted: $path"
                count=$((count + 1))
            else
                echo "DELETE_FAIL=$path" >&2
                klog "FAILED to delete '$path' as root"
            fi
        done
        echo "DELETED_COUNT=$count"
        return 0
    fi
    mkdir -p "$HOME/.Trash" 2>/dev/null
    for path in "$@"; do
        [[ -e "$path" || -L "$path" ]] || continue
        if command -v osascript >/dev/null 2>&1; then
            esc=${path//\"/\\\"}
            if osascript -e "tell application \"Finder\" to delete POSIX file \"$esc\"" \
                    >/dev/null 2>&1; then
                base=$(basename "$path")
                klog "trashed '$path' via Finder -> ~/.Trash/$base (restore: Finder 'Put Back', or: mv \"\$HOME/.Trash/$base\" '$path')"
                echo "TRASHED=$path"
                echo "  Trashed: $path"
                count=$((count + 1))
                continue
            fi
        fi
        base=$(basename "$path")
        dest="$HOME/.Trash/${base}.$(date +%s)"
        if mv -- "$path" "$dest" 2>/dev/null; then
            klog "trashed '$path' -> '$dest' (restore: mv '$dest' '$path')"
            echo "TRASHED=$path"
            echo "  Trashed: $path"
            count=$((count + 1))
        else
            echo "TRASH_FAIL=$path" >&2
            klog "FAILED to trash '$path'"
        fi
    done
    echo "TRASHED_COUNT=$count"
    return 0
}

# Ask a yes/no question. Returns 0 only on y/Y.
# Set KAVIMAC_YES=1 to auto-answer yes (non-interactive runs).
confirm() {
    local prompt=${1:-"Continue?"}
    if [[ "${KAVIMAC_YES:-}" == "1" ]]; then
        return 0
    fi
    printf '%s [y/N] ' "$prompt" >&2
    local answer=""
    if [[ -t 0 ]]; then
        IFS= read -r answer || answer=""
    elif [[ -r /dev/tty ]]; then
        IFS= read -r answer </dev/tty || answer=""
    fi
    case "$answer" in
        y|Y) return 0 ;;
        *)   return 1 ;;
    esac
}
