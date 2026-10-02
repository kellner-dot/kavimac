#!/bin/bash
#===============================================================================
# lib/common.sh — KaviMac shared helpers
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

# Append "[YYYY-MM-DD HH:MM:SS] <msg>" to the KaviMac log
klog() {
    local msg=${1:-}
    local logdir="$HOME/Library/Logs"
    mkdir -p "$logdir" 2>/dev/null || true
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" \
        >> "$logdir/kavimac.log" 2>/dev/null || true
    return 0
}

# Move each existing path to the user's Trash instead of deleting it.
# Tries Finder (keeps "Put Back" working), falls back to mv into
# ~/.Trash/<basename>.<epoch>. Emits TRASHED=<path> per item and TRASHED_COUNT.
# Always returns 0 — a failed trash must never abort a run.
trash_first() {
    local count=0
    local path base dest esc
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
