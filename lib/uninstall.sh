#!/bin/bash
#===============================================================================
# lib/uninstall.sh — KaviMac complete app uninstaller + orphan scanner
# Pearcleaner-pattern uninstall: removes the .app bundle plus its caches,
# preferences, logs, Application Support data, Containers, Saved Application
# State, and launchd jobs. Preview + confirm, everything goes to the Trash
# (never raw rm). Protected services (BlueBubbles, RVD/rvd-mac, Tailscale,
# KaviMac) are never touched.
# Requires: lib/common.sh (trash_first, confirm, klog),
#           lib/guard.sh (guard_require),
#           lib/cleanup.sh (_dir_size, _fmt_bytes). Sourced, not executed.
#===============================================================================

# Directories scanned for app leftovers (user + system-level launchd).
_UNINSTALL_SCAN_DIRS=(
    "$HOME/Library/Caches"
    "$HOME/Library/Preferences"
    "$HOME/Library/Logs"
    "$HOME/Library/Application Support"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/LaunchAgents"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
)

# Protected services: never uninstalled, never scanned, never trashed.
# Whole-token, case-insensitive match against a label or basename.
_UNINSTALL_PROTECTED="bluebubbles rvd rvd-mac tailscale kavimac"

_uninstall_is_protected() {
    local label="$1" low tok
    low=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    for tok in $_UNINSTALL_PROTECTED; do
        if [[ "$low" =~ (^|[^a-z0-9])$tok([^a-z0-9]|$) ]]; then
            return 0
        fi
    done
    return 1
}

# Size in bytes of a file or directory (0 if missing).
_entry_size() {
    local p="$1"
    if [[ -d "$p" ]]; then
        _dir_size "$p"
    elif [[ -f "$p" ]]; then
        stat -f %z "$p" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Locate the app bundle. Sets _APP_PATH. Returns 0 on success.
_uninstall_app_path() {
    local name="$1" cand
    _APP_PATH=""
    for cand in "/Applications/$name.app" "$HOME/Applications/$name.app"; do
        if [[ -d "$cand" ]]; then
            _APP_PATH="$cand"
            return 0
        fi
    done
    # Spotlight fallback (first display-name match)
    local qname="${name//\'/\'\\\'\'}"
    cand=$(mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == '$qname'" 2>/dev/null | head -n 1)
    if [[ -n "$cand" && -d "$cand" ]]; then
        _APP_PATH="$cand"
        return 0
    fi
    return 1
}

# Collect leftover paths matching the app name or bundle id into _LEFTOVERS.
_collect_uninstall_leftovers() {
    local name="$1" bid="$2" dir p first e
    _LEFTOVERS=()
    local args=()
    first=1
    for p in "$name" "$bid"; do
        [[ -z "$p" || "$p" == "(null)" ]] && continue
        if (( first )); then first=0; else args+=(-o); fi
        args+=(-iname "*${p}*")
    done
    for dir in "${_UNINSTALL_SCAN_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' e; do
            # Never the app bundle itself, never protected services
            [[ "$e" == "$_APP_PATH" ]] && continue
            _uninstall_is_protected "$(basename "$e")" && continue
            _LEFTOVERS+=("$e")
        done < <(find "$dir" -mindepth 1 -maxdepth 1 \( "${args[@]}" \) -print0 2>/dev/null)
    done
}

# --- Complete uninstall of a macOS app ---
uninstall_app() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "Usage: uninstall_app <AppName>"
        echo "APP_NOT_FOUND=1"
        return 1
    fi
    if ! guard_require "$name"; then
        echo "  \"$name\" is a protected service — uninstall blocked."
        echo "PROTECTED=1"
        return 1
    fi
    if ! _uninstall_app_path "$name"; then
        echo "  App \"$name\" not found in /Applications, ~/Applications, or Spotlight."
        echo "APP_NOT_FOUND=1"
        return 1
    fi
    local app="$_APP_PATH"
    echo "=== KaviMac Uninstall: $name ==="
    echo "  App bundle: $app ($(_fmt_bytes "$(_entry_size "$app")"))"

    local bid
    bid=$(mdls -name kMDItemCFBundleIdentifier -raw "$app" 2>/dev/null || true)
    [[ "$bid" == "(null)" ]] && bid=""
    [[ -n "$bid" ]] && echo "  Bundle ID: $bid"

    _collect_uninstall_leftovers "$name" "$bid"
    echo ""
    if ((${#_LEFTOVERS[@]})); then
        echo "  Leftover files and folders:"
        local e s total=0
        for e in "${_LEFTOVERS[@]}"; do
            s=$(_entry_size "$e")
            total=$((total + s))
            printf '    %-9s %s\n' "$(_fmt_bytes "$s")" "$e"
        done
        total=$((total + $(_entry_size "$app")))
        echo ""
        echo "  Total reclaimable: $(_fmt_bytes "$total") (${#_LEFTOVERS[@]} leftover items + app bundle)"
        echo ""
        if ! confirm "Uninstall \"$name\" and move ${#_LEFTOVERS[@]} leftover item(s) to Trash?"; then
            echo "  Cancelled — nothing was removed."
            echo "UNINSTALLED=0"
            return 0
        fi
    else
        echo "  No leftover files found — only the app bundle itself."
        echo ""
        if ! confirm "Move \"$name\" app bundle to Trash?"; then
            echo "  Cancelled — nothing was removed."
            echo "UNINSTALLED=0"
            return 0
        fi
    fi

    trash_first "$app"
    if ((${#_LEFTOVERS[@]})); then
        trash_first "${_LEFTOVERS[@]}"
    fi
    klog "Uninstalled $name ($app): app + ${#_LEFTOVERS[@]} leftover items moved to Trash"
    echo "UNINSTALLED=1"
    echo "  \"$name\" uninstalled — app and leftovers moved to Trash (recoverable)."
}

# Installed app names (lowercase, no .app), newline-separated, built by find_orphans.
_INSTALLED_NAMES=""

# Does an owning app still exist for this leftover entry? Conservative token
# heuristic: reverse-domain entries match on their last component
# (com.valvesoftware.steam -> steam); plain names match on their first
# alphanumeric token (Firefox-12345 -> firefox).
_orphan_owner_exists() {
    local base="$1" lower tok
    lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
    lower="${lower%.plist}"
    lower="${lower%.savedstate}"
    if [[ "$lower" =~ ^(com|org|net|io)\. ]]; then
        tok="${lower##*.}"
    else
        tok="${lower%%[!a-z0-9]*}"
    fi
    [[ -n "$tok" ]] || return 1
    printf '%s' "${_INSTALLED_NAMES:-}" | grep -qxF "$tok"
}

# --- Scan for leftovers from long-removed apps ---
find_orphans() {
    echo "=== KaviMac Orphan Scan ==="
    echo "  Scanning app-support folders for leftovers whose apps are gone..."

    # Installed app names (lowercase, no .app suffix)
    _INSTALLED_NAMES=""
    local a base
    while IFS= read -r a; do
        base=$(basename "$a" .app)
        base=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
        _INSTALLED_NAMES+="$base"$'\n'
    done < <(find /Applications "$HOME/Applications" -maxdepth 1 -name "*.app" 2>/dev/null)

    local -a orphans=() unsure=()
    local dir e b low
    for dir in "${_UNINSTALL_SCAN_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' e; do
            b=$(basename "$e")
            [[ "$b" == .* ]] && continue                      # dotfiles are never orphans
            _uninstall_is_protected "$b" && continue
            low=$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')
            [[ "$low" == com.apple.* ]] && continue            # system, not orphan
            if _orphan_owner_exists "$b"; then
                continue                                      # owning app still installed
            fi
            case "$dir" in
                /Library/LaunchAgents|/Library/LaunchDaemons)
                    unsure+=("$e")                            # system-level: too risky to auto-trash
                    ;;
                *)
                    orphans+=("$e")
                    ;;
            esac
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
    done

    local n=${#orphans[@]}
    echo "ORPHANS_FOUND=$n"
    echo ""
    if (( n )); then
        echo "  Orphaned leftovers (owning app no longer installed):"
        local s total=0
        for e in "${orphans[@]}"; do
            s=$(_entry_size "$e")
            total=$((total + s))
            printf '    %-9s %s\n' "$(_fmt_bytes "$s")" "$e"
        done
        echo ""
        echo "  Total reclaimable: $(_fmt_bytes "$total") ($n items)"
        echo ""
        if ! confirm "Move $n orphaned item(s) to Trash?"; then
            echo "  Cancelled — nothing was removed."
            echo "ORPHANS_REMOVED=0"
        else
            trash_first "${orphans[@]}"
            klog "Orphan scan: moved $n orphaned items to Trash ($(_fmt_bytes "$total") reclaimable)"
            echo "ORPHANS_REMOVED=$n"
            echo "  Moved $n orphaned item(s) to Trash."
        fi
    else
        echo "  No orphaned leftovers found."
        echo "ORPHANS_REMOVED=0"
    fi

    if ((${#unsure[@]})); then
        echo ""
        echo "  Unsure (skipped — left in place):"
        for e in "${unsure[@]}"; do
            echo "    ? $e"
        done
    fi
}
