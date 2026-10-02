#!/bin/bash
#===============================================================================
# lib/languages.sh — KaviGuard language-file pruner
# Conservative opt-in pruner: removes non-English *.lproj resource folders
# from user and local application bundles. Report-only first, then a single
# confirm before anything is trashed.
# Never touches /System. Architecture stripping is disabled by design.
#===============================================================================

# Directories scanned for app bundles
_LANGUAGES_SCAN_DIRS=(/Applications "$HOME/Applications")

# Basenames (case-insensitive) of apps never pruned — protected services
_LANGUAGES_PROTECTED=(BlueBubbles Tailscale kavimac kaviguard rvd)

# Is this an English variant? Keep en.lproj, en_*.lproj, English.lproj.
_is_english_lproj() {
    local name="$1"
    case "$name" in
        en.lproj|en_*.lproj|English.lproj) return 0 ;;
        *) return 1 ;;
    esac
}

# Is this app on the protected-services list? (case-insensitive basename)
# Uses tr-based lowercasing: macOS /bin/bash is 3.2 (no ${var,,}).
_is_protected_app() {
    local lower p
    lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    for p in "${_LANGUAGES_PROTECTED[@]}"; do
        p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
        if [[ "$lower" == "$p" || "$lower" == "$p.app" ]]; then
            return 0
        fi
    done
    return 1
}

# Collect candidate *.lproj folders into the global array LANGUAGES_FOUND.
# Only inside *.app bundles; skips anything under /System and protected apps.
_languages_collect() {
    local app appbase lproj
    LANGUAGES_FOUND=()
    for appdir in "${_LANGUAGES_SCAN_DIRS[@]}"; do
        [[ -d "$appdir" ]] || continue
        while IFS= read -r -d '' app; do
            case "$app" in
                /System/*) continue ;;
            esac
            appbase="$(basename "$app")"
            _is_protected_app "$appbase" && continue
            while IFS= read -r -d '' lproj; do
                _is_english_lproj "$(basename "$lproj")" && continue
                LANGUAGES_FOUND+=("$lproj")
            done < <(find "$app" -type d -name "*.lproj" -print0 2>/dev/null)
        done < <(find "$appdir" -maxdepth 2 -type d -name "*.app" -print0 2>/dev/null)
    done
}

# --- Prune non-English language folders (opt-in, report-only first) ---
prune_languages() {
    echo "=== KaviGuard Language Pruner ==="
    echo "  English variants (en.lproj, en_*.lproj, English.lproj) are always kept."
    echo "  Architecture stripping is disabled by design (it has broken apps before)."
    echo ""
    # NOTE: deliberately global (no `local`) — _languages_collect fills it.
    LANGUAGES_FOUND=()
    _languages_collect
    local n=${#LANGUAGES_FOUND[@]}
    local total=0 b lproj
    for lproj in "${LANGUAGES_FOUND[@]}"; do
        b=$(_dir_size "$lproj")
        total=$((total + b))
    done
    echo "LANGUAGES_FOLDERS=$n"
    echo "LANGUAGES_WOULD_FREE=$total"
    if (( n == 0 )); then
        echo "  No non-English language folders found. Nothing to do."
        echo "LANGUAGES_PRUNED=0"
        echo "LANGUAGES_FREED=0"
        return 0
    fi
    echo "  Found $n non-English language folder(s), reclaimable ~$(_fmt_bytes "$total")."
    echo ""
    if ! confirm "Remove $n non-English language folders (~$(_fmt_bytes "$total"))?"; then
        echo "  Skipped — nothing removed."
        echo "LANGUAGES_PRUNED=0"
        echo "LANGUAGES_FREED=0"
        return 0
    fi
    local pruned=0 freed=0
    for lproj in "${LANGUAGES_FOUND[@]}"; do
        b=$(_dir_size "$lproj")
        if trash_first "$lproj"; then
            pruned=$((pruned + 1))
            freed=$((freed + b))
            klog "Pruned language folder: $lproj (~$(_fmt_bytes "$b"))"
        else
            klog "Skipped (trash failed): $lproj"
        fi
    done
    echo "LANGUAGES_PRUNED=$pruned"
    echo "LANGUAGES_FREED=$freed"
    echo "  Pruned $pruned language folder(s), freed $(_fmt_bytes "$freed")."
    echo "  Architecture stripping is disabled by design (it has broken apps before)."
}
