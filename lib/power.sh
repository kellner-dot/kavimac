#!/bin/bash
#===============================================================================
# lib/power.sh — KaviMac never-sleep / power-assertion verifier + fix
# Philosophy: verify the server stays awake; report drift, never change anything
# unless the user explicitly runs power_fix (kavimac.sh --fix-power).
# Known-good baseline: AC sleep 0, autorestart 1, womp 1. Display may sleep.
# Requires lib/common.sh (confirm, klog) sourced first.
#===============================================================================

# Lid-guard identity (caffeinate assertion held by a user LaunchAgent)
LIDGUARD_LABEL="com.seth.kavimac.lidguard"
LIDGUARD_PLIST="$HOME/Library/LaunchAgents/com.seth.kavimac.lidguard.plist"

lidguard_check() {
    # A lid-close mitigation is alive if any of these hold:
    #  1. Our caffeinate LaunchAgent is loaded
    #  2. A caffeinate -i process is running (assertion held somehow)
    #  3. Amphetamine.app is running (free GUI fallback)
    local why=""
    if ! command -v pgrep >/dev/null 2>&1; then
        echo "Lid-close guard: UNKNOWN — pgrep unavailable"
        echo "LIDGUARD=0"
        return 1
    fi
    if command -v launchctl >/dev/null 2>&1 \
        && launchctl list "$LIDGUARD_LABEL" >/dev/null 2>&1; then
        why="caffeinate LaunchAgent"
    elif pgrep -f "caffeinate -i" >/dev/null 2>&1; then
        why="caffeinate process"
    elif pgrep -i "amphetamine" >/dev/null 2>&1; then
        why="Amphetamine.app"
    fi
    if [[ -n "$why" ]]; then
        echo "Lid-close guard: ACTIVE ($why)"
        echo "LIDGUARD=1"
        return 0
    fi
    echo "Lid-close guard: MISSING — the server is a sleeping laptop right now"
    echo "LIDGUARD=0"
    return 1
}

power_verify() {
    # Report-only: compare current power settings against the known-good
    # baseline and print the exact fix command for each drift. Changes nothing.
    local drift=0
    local sleep_ac="" autorestart="" womp=""
    if command -v pmset >/dev/null 2>&1; then
        sleep_ac=$(pmset -g custom 2>/dev/null \
            | awk '/AC Power/{f=1} f&&/sleep/{print $2; exit}')
        autorestart=$(pmset -g 2>/dev/null | awk '/autorestart/{print $2}')
        womp=$(pmset -g 2>/dev/null | awk '/womp/{print $2}')
    else
        echo "  pmset unavailable — cannot verify power baseline"
        echo "POWER_DRIFT=1"
        return 0
    fi
    echo "--- Power Baseline ---"
    if [[ "$sleep_ac" == "0" ]]; then
        echo "  [ok] AC sleep disabled (sleep=0)"
    else
        echo "  DRIFT: AC sleep is '${sleep_ac:-?}' (expected 0) — fix: sudo pmset -c sleep 0"
        drift=1
    fi
    if [[ "$autorestart" == "1" ]]; then
        echo "  [ok] auto-restart on power loss (autorestart=1)"
    else
        echo "  DRIFT: autorestart is '${autorestart:-?}' (expected 1) — fix: sudo pmset -c autorestart 1"
        drift=1
    fi
    if [[ "$womp" == "1" ]]; then
        echo "  [ok] wake for network access (womp=1)"
    else
        echo "  DRIFT: womp is '${womp:-?}' (expected 1) — fix: sudo pmset -c womp 1"
        drift=1
    fi
    echo "--- Lid-Close Guard ---"
    if ! lidguard_check; then
        drift=1
    fi
    echo "POWER_DRIFT=$drift"
    return "$drift"
}

power_fix() {
    # Opt-in: re-apply the known-good power baseline and install the
    # lid-close guard. Does nothing unless the user confirms.
    local changed="pmset"
    if ! confirm "Re-apply server power baseline (sleep 0, autorestart 1, womp 1) and install lid-close guard?"; then
        echo "POWER_FIXED=0"
        return 0
    fi
    sudo pmset -c sleep 0
    sudo pmset -c autorestart 1
    sudo pmset -c womp 1
    klog "power: re-applied baseline (sleep 0, autorestart 1, womp 1)"
    # Install the lid-guard LaunchAgent if missing
    if [[ ! -f "$LIDGUARD_PLIST" ]]; then
        cat > "$LIDGUARD_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.seth.kavimac.lidguard</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-i</string>
    <string>-s</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
PLIST
        klog "power: installed lid-guard LaunchAgent $LIDGUARD_PLIST"
        changed="$changed, lid-guard plist"
    fi
    if command -v launchctl >/dev/null 2>&1 \
        && ! launchctl list "$LIDGUARD_LABEL" >/dev/null 2>&1; then
        launchctl load -w "$LIDGUARD_PLIST" 2>/dev/null \
            || launchctl load "$LIDGUARD_PLIST" 2>/dev/null || true
        klog "power: loaded lid-guard LaunchAgent"
        changed="$changed, lid-guard loaded"
    fi
    echo "Server power baseline re-applied. Changed: $changed"
    echo "POWER_FIXED=1"
}
