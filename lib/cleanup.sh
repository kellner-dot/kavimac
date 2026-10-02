#!/bin/bash
#===============================================================================
# lib/cleanup.sh — KaviMac cleanup functions (v1.1.0 "Server Guard")
# Safe system cleanup: caches, logs, tmp scratch, trash. Reports space freed.
# Preview-by-default: run_cleanup builds a plan, shows per-item + total sizes,
# and asks before applying (pass --yes or set KAVIMAC_YES=1 for trusted reruns).
# Undoable-by-default: everything is trash-first via trash_first(); only
# emptying the Trash itself uses rm. Old logs keep the 7-day rule.
# Never touches user documents, photos, music, or app data.
#
# Sourced, not executed (no shebang). lib/common.sh must be sourced first for:
#   _dir_size, _fmt_bytes, trash_first, confirm, klog
#===============================================================================

# --- Cleanup plan ------------------------------------------------------------
# A plan is a list of entries: key, label, action, size (bytes), note, paths.
# Actions: trash (move paths to Trash), rm (empty Trash contents),
#          flush (DNS flush, non-destructive), skip (not applied; note says why).
_PLAN_KEYS=(); _PLAN_LABELS=(); _PLAN_ACTIONS=(); _PLAN_SIZES=()
_PLAN_NOTES=(); _PLAN_PATHS=()

_plan_reset() {
    _PLAN_KEYS=(); _PLAN_LABELS=(); _PLAN_ACTIONS=(); _PLAN_SIZES=()
    _PLAN_NOTES=(); _PLAN_PATHS=()
}

# _plan_add <key> <label> <action> <size-bytes> <note> [paths...]
_plan_add() {
    local key="$1" label="$2" action="$3" size="$4" note="$5"; shift 5
    local p joined=""
    for p in "$@"; do
        [[ -n "${p:-}" ]] || continue
        joined+="${p}"$'\n'
    done
    _PLAN_KEYS+=( "$key" )
    _PLAN_LABELS+=( "$label" )
    _PLAN_ACTIONS+=( "$action" )
    _PLAN_SIZES+=( "$size" )
    _PLAN_NOTES+=( "$note" )
    _PLAN_PATHS+=( "$joined" )
}

# Total size in bytes of a list of FILES (missing entries count 0).
# _dir_size (common.sh) covers directories; this one covers file lists.
_files_size() {
    local total=0 f kb
    for f in "$@"; do
        [[ -f "${f:-}" ]] || continue
        kb=$(du -sk "$f" 2>/dev/null | awk '{print $1}')
        total=$(( total + ${kb:-0} * 1024 ))
    done
    echo "$total"
}

# --- Plan builders (no changes made; each adds one plan entry) ---------------

# --- User caches (safe: apps rebuild them) ---
cleanup_user_caches() {
    local dir="$HOME/Library/Caches"
    if [[ ! -d "$dir" ]]; then
        _plan_add "USER_CACHES" "User caches" "skip" 0 "not present"
        return 0
    fi
    local -a targets=()
    while IFS= read -r e; do
        [[ -n "${e:-}" ]] && targets+=( "$e" )
    done < <(find "$dir" -mindepth 1 -maxdepth 1 \
        ! -name "com.apple.Safari" \
        ! -name "com.apple.finder" 2>/dev/null)
    local size=0 e
    for e in ${targets[@]+"${targets[@]}"}; do
        size=$(( size + $(_dir_size "$e") ))
    done
    _plan_add "USER_CACHES" "User caches" "trash" "$size" "" ${targets[@]+"${targets[@]}"}
}

# --- System caches (needs sudo; safe subset only) ---
cleanup_system_caches() {
    if [[ $EUID -ne 0 ]]; then
        _plan_add "SYSTEM_CACHES" "System caches" "skip" 0 "needs sudo"
        return 0
    fi
    if [[ ! -d "/Library/Caches" ]]; then
        _plan_add "SYSTEM_CACHES" "System caches" "skip" 0 "not present"
        return 0
    fi
    local -a targets=()
    while IFS= read -r e; do
        [[ -n "${e:-}" ]] && targets+=( "$e" )
    done < <(find /Library/Caches -mindepth 1 -maxdepth 1 -name "com.apple.*" 2>/dev/null)
    local size=0 e
    for e in ${targets[@]+"${targets[@]}"}; do
        size=$(( size + $(_dir_size "$e") ))
    done
    _plan_add "SYSTEM_CACHES" "System caches" "trash" "$size" "" ${targets[@]+"${targets[@]}"}
}

# --- Trash (emptying it is the point, so this one uses rm on its contents) ---
cleanup_trash() {
    local -a tdirs=()
    [[ -d "$HOME/.Trash" ]] && tdirs+=( "$HOME/.Trash" )
    local vol
    for vol in /Volumes/*/.Trashes/$UID; do
        [[ -d "$vol" ]] && tdirs+=( "$vol" )
    done
    local size=0 t
    for t in ${tdirs[@]+"${tdirs[@]}"}; do
        size=$(( size + $(_dir_size "$t") ))
    done
    _plan_add "TRASH" "Trash (empty)" "rm" "$size" "" ${tdirs[@]+"${tdirs[@]}"}
}

# --- Old logs (keep last 7 days; system logs need sudo) ---
cleanup_logs() {
    local -a files=()
    local ulog="$HOME/Library/Logs"
    if [[ -d "$ulog" ]]; then
        while IFS= read -r -d '' f; do
            files+=( "$f" )
        done < <(find "$ulog" -type f -mtime +7 -print0 2>/dev/null)
    fi
    local note=""
    if [[ $EUID -eq 0 ]]; then
        while IFS= read -r -d '' f; do
            files+=( "$f" )
        done < <(find /var/log -type f \( -name "*.log.*" -o -name "*.gz" \) \
            -mtime +7 -print0 2>/dev/null)
    else
        note="system logs need sudo"
    fi
    local size
    size=$(_files_size ${files[@]+"${files[@]}"})
    _plan_add "LOGS" "Old logs (>7 days)" "trash" "$size" "$note" ${files[@]+"${files[@]}"}
}

# --- DNS cache (non-destructive flush) ---
cleanup_dns_cache() {
    _plan_add "DNS" "DNS cache" "flush" 0 ""
}

# --- Xcode derived data (dev junk, often GBs) ---
cleanup_xcode_derived() {
    local dd="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ ! -d "$dd" ]]; then
        _plan_add "XCODE" "Xcode DerivedData" "skip" 0 "not present"
        return 0
    fi
    local -a targets=()
    while IFS= read -r e; do
        [[ -n "${e:-}" ]] && targets+=( "$e" )
    done < <(find "$dd" -mindepth 1 -maxdepth 1 2>/dev/null)
    local size
    size=$(_dir_size "$dd")
    _plan_add "XCODE" "Xcode DerivedData" "trash" "$size" "" ${targets[@]+"${targets[@]}"}
}

# --- Temp files: files (not dirs) in /private/tmp older than 3 days ---
cleanup_tmp() {
    local -a files=()
    if [[ -d "/private/tmp" ]]; then
        while IFS= read -r -d '' f; do
            files+=( "$f" )
        done < <(find /private/tmp -maxdepth 1 -type f -mtime +3 -print0 2>/dev/null)
    fi
    local size
    size=$(_files_size ${files[@]+"${files[@]}"})
    _plan_add "TMP" "Temp files (/private/tmp, >3 days)" "trash" "$size" "" ${files[@]+"${files[@]}"}
}

# --- var/folders scratch: current user's per-user T dirs, files older than 3 days ---
cleanup_varfolders() {
    local -a files=()
    local t
    for t in /var/folders/*/*/T/; do
        [[ -d "$t" && -O "$t" ]] || continue
        while IFS= read -r -d '' f; do
            files+=( "$f" )
        done < <(find "$t" -type f -mtime +3 -print0 2>/dev/null)
    done
    if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
        while IFS= read -r -d '' f; do
            files+=( "$f" )
        done < <(find "$TMPDIR" -type f -mtime +3 -print0 2>/dev/null)
    fi
    local size
    size=$(_files_size ${files[@]+"${files[@]}"})
    _plan_add "VARFOLDERS" "var/folders scratch (>3 days)" "trash" "$size" "" ${files[@]+"${files[@]}"}
}

# --- Preview: print the plan table with per-item and total sizes -------------
_plan_print() {
    local i n=${#_PLAN_KEYS[@]}
    echo ""
    echo "Preview — nothing has been removed yet:"
    printf "  %-36s %12s  %s\n" "ITEM" "SIZE" "STATUS"
    local total=0 label size action note status
    for (( i = 0; i < n; i++ )); do
        label="${_PLAN_LABELS[$i]}"; size="${_PLAN_SIZES[$i]}"
        action="${_PLAN_ACTIONS[$i]}"; note="${_PLAN_NOTES[$i]}"
        status=""
        case "$action" in
            skip)  status="skipped: $note" ;;
            flush) status="non-destructive" ;;
            rm)    status="will empty (rm)" ;;
            trash)
                if (( size == 0 )); then status="nothing to remove"
                else status="to Trash"; fi
                ;;
        esac
        if [[ "$action" != "skip" && -n "$note" ]]; then
            status="${status:+$status; }$note"
        fi
        printf "  %-36s %12s  %s\n" "$label" "$(_fmt_bytes "$size")" "$status"
        total=$(( total + size ))
    done
    printf "  %-36s %12s\n" "------------------------------------" "------------"
    printf "  %-36s %12s\n" "TOTAL (planned)" "$(_fmt_bytes "$total")"
    echo ""
}

# --- Apply: execute the plan, emit MACHINE *_FREED= lines + human lines -------
_plan_apply() {
    local i n=${#_PLAN_KEYS[@]}
    local total=0
    local -a removed=() skipped=()
    local key label action size paths p
    for (( i = 0; i < n; i++ )); do
        key="${_PLAN_KEYS[$i]}"; label="${_PLAN_LABELS[$i]}"
        action="${_PLAN_ACTIONS[$i]}"; size="${_PLAN_SIZES[$i]}"
        local -a paths=()
        while IFS= read -r p; do
            [[ -n "${p:-}" ]] && paths+=( "$p" )
        done <<< "${_PLAN_PATHS[$i]}"
        case "$action" in
            trash)
                if (( ${#paths[@]} > 0 )); then
                    trash_first "${paths[@]}"
                fi
                echo "${key}_FREED=$size"
                echo "  $label: freed $(_fmt_bytes "$size") (moved to Trash)"
                (( size > 0 )) && removed+=( "$label $(_fmt_bytes "$size")" )
                total=$(( total + size ))
                ;;
            rm)
                for p in ${paths[@]+"${paths[@]}"}; do
                    [[ -d "$p" ]] || continue
                    rm -rf "${p:?}/"* 2>/dev/null
                done
                echo "${key}_FREED=$size"
                echo "  $label: freed $(_fmt_bytes "$size")"
                (( size > 0 )) && removed+=( "$label $(_fmt_bytes "$size")" )
                total=$(( total + size ))
                ;;
            flush)
                dscacheutil -flushcache 2>/dev/null
                killall -HUP mDNSResponder 2>/dev/null
                echo "${key}_FLUSHED=1"
                echo "  $label: flushed"
                ;;
            skip)
                echo "${key}_FREED=0"
                echo "  $label: skipped (${_PLAN_NOTES[$i]})"
                skipped+=( "$label (${_PLAN_NOTES[$i]})" )
                ;;
        esac
    done
    echo ""
    echo "TOTAL_FREED=$total"
    echo "Total freed: $(_fmt_bytes "$total")"
    klog "cleanup: applied; freed $(_fmt_bytes "$total"); removed: ${removed[*]:-none}; skipped: ${skipped[*]:-none}"
}

# --- Run all cleanup: plan -> preview -> confirm -> apply --------------------
# run_cleanup [--yes]
run_cleanup() {
    local yes=0
    [[ "${1:-}" == "--yes" ]] && yes=1
    [[ "${KAVIMAC_YES:-}" == "1" ]] && yes=1

    echo "=== KaviMac Cleanup ==="

    # Phase 1: build the plan (no changes made)
    _plan_reset
    cleanup_user_caches
    cleanup_system_caches
    cleanup_trash
    cleanup_logs
    cleanup_dns_cache
    cleanup_xcode_derived
    cleanup_tmp
    cleanup_varfolders

    # Phase 2: preview
    _plan_print

    # Phase 3: confirm (unless --yes / KAVIMAC_YES=1)
    if (( yes == 0 )); then
        if ! confirm "Apply this cleanup?"; then
            echo "CLEANUP_ABORTED=1"
            klog "cleanup: aborted at preview by user; nothing removed"
            return 0
        fi
    fi

    # Phase 4: apply
    _plan_apply
}
