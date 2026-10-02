#!/bin/bash
#===============================================================================
# lib/startup.sh — KaviMac startup & launchd manager (v1.1 "Server Guard")
#
# One view of ALL login items + LaunchAgents/Daemons, with guarded interactive
# disable. Philosophy: list first, disable only with two confirmations
# (number + confirm), and never touch protected services (BlueBubbles, the
# RVD agent, Tailscale, KaviMac).
#
# Every disable is reversible: `launchctl unload` stops the job, the plist
# moves to Trash via trash_first(), and the restore path is echoed and klog'd.
# Login Items are report-only (managed in System Settings > General > Login
# Items) — there is no safe reversible CLI for them.
#
# Sourced by kavimac.sh — no shebang. Must stay `set -u` safe and run under
# the stock macOS bash (3.2): no associative arrays, no ${var,,}, no mapfile.
# Expects lib/common.sh (confirm, klog, trash_first) and lib/guard.sh
# (guard_is_protected) to be sourced first. Degrades gracefully when sfltool
# or launchctl are missing.
#===============================================================================

# --- private helpers ---------------------------------------------------------

# _su_is_protected <label> — exit 0 if the entry is on the protected whitelist.
# Uses guard_is_protected() from lib/guard.sh when available; otherwise falls
# back to a built-in pattern list (guard.sh is authoritative when present).
_su_is_protected() {
    local name="$1"
    if declare -F guard_is_protected >/dev/null 2>&1; then
        guard_is_protected "$name"
        return $?
    fi
    local lower
    lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *bluebubbles*|*rvd-mac*|*rvd*agent*|*tailscale*|*kavimac*) return 0 ;;
        *) return 1 ;;
    esac
}

# _su_friendly <label> — plain-English guess from a reverse-DNS label, e.g.
# "com.google.keystone.agent" -> "Google Keystone Agent".
# Prints "unknown — research before disabling" when nothing usable remains.
_su_friendly() {
    local label="$1"
    local guess
    guess=$(printf '%s' "$label" \
        | sed -E 's/^(com|org|net|io|edu|gov|us|uk|co)\.//' \
        | tr '._-' '   ' \
        | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print }')
    guess=$(printf '%s' "$guess" | sed 's/^ *//; s/ *$//')
    if [[ -z "$guess" ]]; then
        printf '%s' "unknown — research before disabling"
    else
        printf '%s' "$guess"
    fi
}

# _su_login_items_raw — one login-item name per line from `sfltool dumpbtm`;
# prints nothing when sfltool is missing or finds no Login Item entries.
_su_login_items_raw() {
    if ! command -v sfltool >/dev/null 2>&1; then
        return 0
    fi
    sfltool dumpbtm 2>/dev/null | awk '
        /^ *Name:[ ]/ { name = $0; sub(/^ *Name:[ ]*/, "", name) }
        /Type:.*Login Item/ && name != "" { print name; name = "" }
    '
}

# _su_remove_master <label> — drop a disabled entry from the master arrays.
_su_remove_master() {
    local gone="$1"
    local i=0
    local keep_l=() keep_p=() keep_d=()
    local total=${#_SU_LABEL[@]}
    for (( i = 0; i < total; i++ )); do
        if [[ "${_SU_LABEL[$i]}" != "$gone" ]]; then
            keep_l[${#keep_l[@]}]="${_SU_LABEL[$i]}"
            keep_p[${#keep_p[@]}]="${_SU_PLIST[$i]}"
            keep_d[${#keep_d[@]}]="${_SU_DOMAIN[$i]}"
        fi
    done
    if (( ${#keep_l[@]} > 0 )); then
        _SU_LABEL=("${keep_l[@]}")
        _SU_PLIST=("${keep_p[@]}")
        _SU_DOMAIN=("${keep_d[@]}")
    else
        _SU_LABEL=(); _SU_PLIST=(); _SU_DOMAIN=()
    fi
}

# _su_render_table — rebuild the disablable-entry arrays from the master
# arrays and print the unified LaunchAgents/Daemons table. Sets the global
# _SU_DISABLABLE to the number of numbered (non-protected) entries.
_su_render_table() {
    _SU_D_LABEL=(); _SU_D_PLIST=(); _SU_D_DOMAIN=()
    _SU_DISABLABLE=0
    echo "--- Launch Agents & Daemons ---"
    local total=${#_SU_LABEL[@]}
    if (( total == 0 )); then
        echo "  none found"
        return 0
    fi
    printf '  %-3s %-38s %-7s %-10s %s\n' "#" "Label" "Domain" "Status" "What it is"
    local i=0
    local n=0
    local protected_count=0
    local have_launchctl=0
    command -v launchctl >/dev/null 2>&1 && have_launchctl=1
    for (( i = 0; i < total; i++ )); do
        local label="${_SU_LABEL[$i]}"
        local domain="${_SU_DOMAIN[$i]}"
        local friendly
        friendly=$(_su_friendly "$label")
        local status="n/a"
        if (( have_launchctl == 1 )); then
            if launchctl list "$label" >/dev/null 2>&1; then
                status="loaded"
            else
                status="not loaded"
            fi
        fi
        local num="--"
        local desc="$friendly"
        if _su_is_protected "$label"; then
            desc="${friendly} [protected — cannot disable]"
            protected_count=$((protected_count + 1))
        else
            n=$((n + 1))
            num="${n}."
            _SU_D_LABEL[${#_SU_D_LABEL[@]}]="$label"
            _SU_D_PLIST[${#_SU_D_PLIST[@]}]="${_SU_PLIST[$i]}"
            _SU_D_DOMAIN[${#_SU_D_DOMAIN[@]}]="$domain"
        fi
        printf '  %-3s %-38.38s %-7s %-10s %s\n' "$num" "$label" "$domain" "$status" "$desc"
    done
    echo "  ${protected_count} protected (locked), ${n} eligible for disable"
    _SU_DISABLABLE=$n
}

# _su_disable_entry <label> <plist> <domain> — reversible disable:
# launchctl unload, then plist -> Trash via trash_first(). Restore path is
# echoed and klog'd. Never call on a protected entry.
_su_disable_entry() {
    local label="$1"
    local plist="$2"
    local domain="$3"
    local base orig_dir
    base=$(basename "$plist")
    orig_dir=$(dirname "$plist")

    # 1. Unload the job from launchd.
    if command -v launchctl >/dev/null 2>&1; then
        if [[ "$domain" == "user" ]]; then
            if launchctl unload "$plist" >/dev/null 2>&1; then
                echo "  Unloaded '${label}' (user domain)."
            else
                echo "  Note: '${label}' was not loaded — nothing to unload."
            fi
        else
            echo "  System-domain entry — using sudo to unload."
            if sudo launchctl unload "$plist" >/dev/null 2>&1; then
                echo "  Unloaded '${label}' (system domain)."
            else
                echo "  Note: unload failed or '${label}' was not loaded."
            fi
        fi
    else
        echo "  launchctl not available — skipping unload, moving plist only."
    fi

    # 2. Reversible disable: plist -> Trash.
    trash_first "$plist"
    if [[ -f "$plist" ]]; then
        echo "  WARNING: '${plist}' is still present — trash_first may have failed."
        klog "startup: FAILED to trash plist for '${label}' (${plist}); unload state above"
        return 1
    fi
    local restore="Restore: move '${base}' from Trash back to '${orig_dir}'"
    echo "  Disabled '${label}' — plist moved to Trash."
    echo "  ${restore}"
    klog "startup: disabled '${label}' (plist moved to Trash). ${restore}"
    return 0
}

# --- public entry point ------------------------------------------------------

# startup_list — unified startup inventory + interactive manager.
# Default action is list-only. Disabling requires two confirmations:
# picking a number, then confirm(). Protected entries can never be disabled.
# Emits machine-readable STARTUP_ITEMS and STARTUP_DISABLED lines.
startup_list() {
    echo "=== KaviMac Startup Manager ==="
    echo ""

    # ---- 1. Login Items --------------------------------------------------
    echo "--- Login Items ---"
    local login_raw=""
    local login_count=0
    if command -v sfltool >/dev/null 2>&1; then
        login_raw=$(_su_login_items_raw)
        if [[ -n "$login_raw" ]]; then
            login_count=$(printf '%s\n' "$login_raw" | grep -c .)
            printf '%s\n' "$login_raw" | sed 's/^/  * /'
            echo "  (report only — remove in System Settings > General > Login Items)"
        else
            echo "  none"
        fi
    else
        echo "  sfltool not available — falling back to user LaunchAgents list:"
        local f=""
        local fb_count=0
        for f in "$HOME/Library/LaunchAgents"/*.plist; do
            [[ -f "$f" ]] || continue
            echo "    $(basename "$f" .plist)"
            fb_count=$((fb_count + 1))
        done
        (( fb_count == 0 )) && echo "    (none)"
        echo "  (same entries appear under Launch Agents below — not double-counted)"
    fi
    echo ""

    # ---- 2. LaunchAgents / LaunchDaemons ----------------------------------
    _SU_LABEL=(); _SU_PLIST=(); _SU_DOMAIN=()
    local dir=""
    for dir in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
        [[ -d "$dir" ]] || continue
        local domain="system"
        [[ "$dir" == "$HOME"* ]] && domain="user"
        local plist=""
        for plist in "$dir"/*.plist; do
            [[ -f "$plist" ]] || continue
            _SU_LABEL[${#_SU_LABEL[@]}]="$(basename "$plist" .plist)"
            _SU_PLIST[${#_SU_PLIST[@]}]="$plist"
            _SU_DOMAIN[${#_SU_DOMAIN[@]}]="$domain"
        done
    done
    local launchd_count=${#_SU_LABEL[@]}

    _su_render_table

    # ---- 3. Interactive manager (list-only unless confirmed twice) -------
    local disabled=""
    if [[ -t 0 ]] && (( _SU_DISABLABLE > 0 )); then
        while true; do
            echo ""
            local choice=""
            read -rp "Disable which number? (Enter to skip, 'q' to quit) " choice || break
            if [[ -z "$choice" || "$choice" == [qQ] ]]; then
                break
            fi
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > _SU_DISABLABLE )); then
                echo "  Enter a number 1-${_SU_DISABLABLE}, Enter to skip, or 'q'."
                continue
            fi
            local di=$((choice - 1))
            local dlabel="${_SU_D_LABEL[$di]}"
            local dplist="${_SU_D_PLIST[$di]}"
            local ddomain="${_SU_D_DOMAIN[$di]}"
            # Belt-and-suspenders: protected entries are never numbered, but
            # re-check anyway in case the whitelist changed mid-run.
            if _su_is_protected "$dlabel"; then
                echo "  BLOCKED: '${dlabel}' is protected and cannot be disabled."
                klog "startup: BLOCKED disable attempt on protected entry '${dlabel}'"
                continue
            fi
            if ! confirm "Disable '${dlabel}'? Its plist moves to Trash (reversible)."; then
                echo "  Skipped '${dlabel}'."
                continue
            fi
            if _su_disable_entry "$dlabel" "$dplist" "$ddomain"; then
                if [[ -z "$disabled" ]]; then
                    disabled="$dlabel"
                else
                    disabled="${disabled},${dlabel}"
                fi
                _su_remove_master "$dlabel"
                echo ""
                _su_render_table
                if (( _SU_DISABLABLE == 0 )); then
                    echo "  Nothing left to disable."
                    break
                fi
            fi
        done
    elif (( _SU_DISABLABLE > 0 )); then
        echo ""
        echo "  (non-interactive session — list only; run in a terminal to manage)"
    fi

    # ---- 4. Machine-readable summary -------------------------------------
    local total_items=$((login_count + launchd_count))
    echo ""
    klog "startup: inventoried ${total_items} startup items (${login_count} login items, ${launchd_count} launchd entries)"
    echo "STARTUP_ITEMS=${total_items}"
    if [[ -z "$disabled" ]]; then
        echo "STARTUP_DISABLED=0"
    else
        echo "STARTUP_DISABLED=${disabled}"
    fi
}
