#!/bin/bash
#===============================================================================
# tests/selftest.sh — KaviGuard v1.1.0 self-test (Linux-safe)
# Mocks macOS-only commands (pmset, tmutil, osascript, curl, ...) via a fake
# bin dir prepended to PATH, then exercises the pure-bash helpers and the
# preview/guard logic. Run: ./tests/selftest.sh
#===============================================================================
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TDIR=$(mktemp -d /tmp/kavimac-test.XXXXXX)
MOCKBIN="$TDIR/bin"
FAKEHOME="$TDIR/home"
mkdir -p "$MOCKBIN" "$FAKEHOME"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
check() { # check <desc> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}

# --- Mock commands -----------------------------------------------------------
# curl: honors MOCK_BB_UP / MOCK_RVG_UP; supports -w http_code
cat > "$MOCKBIN/curl" <<'EOF'
#!/bin/bash
url="${@: -1}"
code=000
case "$url" in
  *":1234/"*)        [[ "${MOCK_BB_UP:-1}" == "1" ]] && code=200 || code=000 ;;
  *":8899/rvd/status"*) [[ "${MOCK_RVG_UP:-1}" == "1" ]] && code=200 || code=000 ;;
esac
for a in "$@"; do [[ "$a" == "-w" ]] && { echo -n "$code"; exit 0; }; done
[[ "$code" == "000" ]] && exit 7 || exit 0
EOF
cat > "$MOCKBIN/pgrep" <<'EOF'
#!/bin/bash
# pgrep [-x name] | [-f pattern] | [-i pattern]
pat="${@: -1}"
case "$pat" in
  tailscaled|tailscale) [[ "${MOCK_TS_UP:-1}" == "1" ]] && { echo 4242; exit 0; } || exit 1 ;;
  kavimac-monitor)      echo 4343; exit 0 ;;
  "caffeinate -i")      [[ "${MOCK_LIDGUARD:-0}" == "1" ]] && { echo 4444; exit 0; } || exit 1 ;;
  amphetamine)          exit 1 ;;
  *) exit 1 ;;
esac
EOF
cat > "$MOCKBIN/launchctl" <<'EOF'
#!/bin/bash
# launchctl list <label> | launchctl kickstart ... | load ...
[[ "$1" == "list" ]] || exit 0
case "$2" in
  com.seth.kaviguard)          exit 0 ;;
  com.seth.kavimac.lidguard)  [[ "${MOCK_LIDGUARD:-0}" == "1" ]] && exit 0 || exit 1 ;;
  *) exit 1 ;;
esac
EOF
cat > "$MOCKBIN/pmset" <<'EOF'
#!/bin/bash
if [[ "$1" == "-g" && "$2" == "custom" ]]; then
    echo "AC Power:"
    echo " sleep                ${MOCK_SLEEP:-0}"
elif [[ "$1" == "-g" && $# -eq 1 ]]; then
    echo " autorestart          ${MOCK_AUTORestart:-1}"
    echo " womp                 ${MOCK_WOMP:-1}"
fi
exit 0
EOF
cat > "$MOCKBIN/tmutil" <<'EOF'
#!/bin/bash
if [[ "$1" == "listlocalsnapshots" ]]; then
    if [[ "${MOCK_SNAPS:-1}" == "1" ]]; then
        echo "com.apple.TimeMachine.2026-09-30-120000.local"
        echo "com.apple.TimeMachine.2026-10-01-120000.local"
    else
        echo "No local snapshots found"
    fi
elif [[ "$1" == "thinlocalsnapshots" ]]; then
    [[ "${MOCK_THIN_OK:-1}" == "1" ]] && exit 0 || exit 1
fi
exit 0
EOF
cat > "$MOCKBIN/diskutil" <<'EOF'
#!/bin/bash
echo "   Purgeable Space:     12.5 GB (13421772800 Bytes)"
exit 0
EOF
cat > "$MOCKBIN/lsof" <<'EOF'
#!/bin/bash
echo 1234; exit 0   # lsof -ti :port
EOF
cat > "$MOCKBIN/ps" <<'EOF'
#!/bin/bash
echo "10:23"; exit 0  # ps -o etime= -p <pid>
EOF
cat > "$MOCKBIN/sysctl" <<'EOF'
#!/bin/bash
# Realistic per-key macOS sysctl output (used by the swap-parsing regression test)
case "$*" in
  *vm.swapusage*)  echo "total = 4096.00M  used = 1536.00M  free = 2560.00M  (encrypted)" ;;
  *kern.boottime*) echo "{ sec = 1000000, usec = 0 }" ;;
  *hw.memsize*)    echo "8589934592" ;;
  *vm.loadavg*)    echo "{ 1.20 1.05 0.90 }" ;;
  *) echo "" ;;
esac
exit 0
EOF
cat > "$MOCKBIN/osascript" <<'EOF'
#!/bin/bash
exit 1   # force trash_first mv fallback on Linux
EOF
cat > "$MOCKBIN/sleep" <<'EOF'
#!/bin/bash
exit 0   # keep monitor tests fast
EOF
cat > "$MOCKBIN/open" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$MOCKBIN"/*

export PATH="$MOCKBIN:$PATH"
export HOME="$FAKEHOME"
export REPO MOCKBIN FAKEHOME TDIR

# Run a snippet with NO controlling terminal, so confirm()'s /dev/tty fallback
# fails closed (decline) instead of blocking. Usage: no_tty '<bash snippet>'.
# Snippet runs with the mock bin on PATH and the fake HOME; libs are sourced.
no_tty() {
    setsid env "PATH=$MOCKBIN:$PATH" "HOME=$FAKEHOME" "REPO=$REPO" \
        "SNIPPET=$1" \
        bash -c 'source "$REPO/lib/common.sh"
                  source "$REPO/lib/guard.sh"
                  source "$REPO/lib/cleanup.sh"
                  source "$REPO/lib/maintenance.sh"
                  eval "$SNIPPET"' </dev/null 2>&1
}

# Source the real libs (order matters, like kavimac.sh)
# shellcheck disable=SC1091
source "$REPO/lib/common.sh"
# shellcheck disable=SC1091
source "$REPO/lib/guard.sh"
# shellcheck disable=SC1091
source "$REPO/lib/cleanup.sh"
# shellcheck disable=SC1091
source "$REPO/lib/power.sh"
# shellcheck disable=SC1091
source "$REPO/lib/disk.sh"
# shellcheck disable=SC1091
source "$REPO/lib/startup.sh"
# shellcheck disable=SC1091
source "$REPO/lib/uninstall.sh"
# shellcheck disable=SC1091
source "$REPO/lib/languages.sh"
# shellcheck disable=SC1091
source "$REPO/lib/maintenance.sh"
# shellcheck disable=SC1091
source "$REPO/lib/optimize.sh"
# shellcheck disable=SC1091
source "$REPO/lib/services.sh"

echo "== common.sh =="
check "_fmt_bytes 0"        "0 B"    "$(_fmt_bytes 0)"
check "_fmt_bytes 1536"     "1.5 KB" "$(_fmt_bytes 1536)"
check "_fmt_bytes 5242880"  "5.0 MB" "$(_fmt_bytes 5242880)"
check "_fmt_bytes 2147483648" "2.0 GB" "$(_fmt_bytes 2147483648)"
check "_dir_size missing"   "0"      "$(_dir_size /nope/nothing)"
echo "hello" > "$FAKEHOME/doomed.txt"
out=$(KAVIGUARD_RM_MODE=trash trash_first "$FAKEHOME/doomed.txt")
check "trash_first count"   "TRASHED_COUNT=1" "$(echo "$out" | grep TRASHED_COUNT)"
[[ ! -e "$FAKEHOME/doomed.txt" && -n "$(ls "$FAKEHOME/.Trash"/doomed.txt.* 2>/dev/null)" ]] \
    && ok "trash_first moved file to ~/.Trash" || bad "trash_first moved file"
grep -q "restore:" "$FAKEHOME/Library/Logs/kavimac.log" \
    && ok "klog recorded restore path" || bad "klog restore path"
# rm-direct mode (the sudo path): deletes outright, never touches Trash
echo "hello" > "$FAKEHOME/doomed2.txt"
out=$(KAVIGUARD_RM_MODE=rm trash_first "$FAKEHOME/doomed2.txt")
check "trash_first rm count" "DELETED_COUNT=1" "$(echo "$out" | grep DELETED_COUNT)"
[[ ! -e "$FAKEHOME/doomed2.txt" && -z "$(ls "$FAKEHOME/.Trash"/doomed2.txt* 2>/dev/null)" ]] \
    && ok "trash_first rm mode deletes directly, skips Trash" || bad "trash_first rm mode"
KAVIGUARD_RM_MODE=rm _use_direct_rm; check "_use_direct_rm forced rm" "0" "$?"
KAVIGUARD_RM_MODE=trash _use_direct_rm; check "_use_direct_rm forced trash" "1" "$?"
KAVIMAC_YES=1 confirm "x" && ok "confirm honors KAVIMAC_YES=1" || bad "confirm KAVIMAC_YES"
KAVIMAC_YES=0
# decline path must not block on /dev/tty → run with no controlling terminal
no_tty 'confirm "x" >/dev/null 2>&1' && bad "confirm decline" || ok "confirm declines with no tty"

echo "== guard.sh =="
guard_is_protected "BlueBubbles Server" && ok "guard matches BlueBubbles" || bad "guard BlueBubbles"
guard_is_protected "rvd-mac agent"      && ok "guard matches rvd-mac"      || bad "guard rvd-mac"
guard_is_protected "Tailscale"          && ok "guard matches Tailscale"    || bad "guard Tailscale"
guard_is_protected "Safari"            && bad "guard false positive"      || ok "guard ignores Safari"
guard_require "BlueBubbles" 2>/dev/null && bad "guard_require blocks"     || ok "guard_require blocks BlueBubbles"
guard_require "VLC" 2>/dev/null         && ok "guard_require allows VLC"  || bad "guard_require VLC"
export MOCK_BB_UP=1 MOCK_RVG_UP=1 MOCK_TS_UP=1
out=$(guard_check); rc=$?
check "guard_check all-up rc" "0" "$rc"
echo "$out" | grep -q "GUARD_OK=1" && ok "guard_check GUARD_OK=1" || bad "guard_check GUARD_OK"
export MOCK_BB_UP=0
out=$(guard_check); rc=$?
check "guard_check bb-down rc" "1" "$rc"
echo "$out" | grep -q "GUARD_OK=0" && ok "guard_check GUARD_OK=0" || bad "guard_check GUARD_OK=0"
export MOCK_BB_UP=1

echo "== cleanup.sh (preview + --yes) =="
mkdir -p "$FAKEHOME/Library/Caches/com.example.app" "$FAKEHOME/Library/Caches/com.apple.Safari"
echo "junk" > "$FAKEHOME/Library/Caches/com.example.app/f.dat"
echo "keep" > "$FAKEHOME/Library/Caches/com.apple.Safari/f.dat"
export KAVIMAC_YES=1
out=$(run_cleanup --yes)
echo "$out" | grep -q "USER_CACHES_FREED=" && ok "cleanup emits USER_CACHES_FREED" || bad "cleanup machine line"
echo "$out" | grep -q "TOTAL_FREED=" && ok "cleanup emits TOTAL_FREED" || bad "cleanup TOTAL_FREED"
[[ ! -e "$FAKEHOME/Library/Caches/com.example.app" ]] && ok "cleanup trashed example cache dir" || bad "cleanup example cache"
[[ -e "$FAKEHOME/Library/Caches/com.apple.Safari/f.dat" ]] && ok "cleanup kept Safari cache" || bad "cleanup Safari exclusion"
unset KAVIMAC_YES
mkdir -p "$FAKEHOME/Library/Caches/com.example.two"
echo "x" > "$FAKEHOME/Library/Caches/com.example.two/f.dat"
out=$(no_tty 'run_cleanup'); rc=$?
echo "$out" | grep -q "CLEANUP_ABORTED=1" && ok "cleanup preview aborts on decline" || bad "cleanup abort"
[[ -e "$FAKEHOME/Library/Caches/com.example.two" ]] && ok "cleanup abort left files alone" || bad "cleanup abort side effects"

echo "== power.sh =="
export MOCK_SLEEP=0 MOCK_AUTORestart=1 MOCK_WOMP=1 MOCK_LIDGUARD=1
out=$(power_verify); rc=$?
check "power_verify baseline rc" "0" "$rc"
echo "$out" | grep -q "POWER_DRIFT=0" && ok "power_verify POWER_DRIFT=0" || bad "power_verify drift"
export MOCK_SLEEP=30 MOCK_LIDGUARD=0
out=$(power_verify); rc=$?
check "power_verify drift rc" "1" "$rc"
echo "$out" | grep -q "POWER_DRIFT=1" && ok "power_verify POWER_DRIFT=1" || bad "power_verify drift=1"
echo "$out" | grep -qi "sleeping laptop" && ok "lidguard missing warns loudly" || bad "lidguard warning"

echo "== disk.sh =="
export MOCK_SNAPS=1
out=$(snapshots_list)
echo "$out" | grep -q "SNAPSHOT_COUNT=2" && ok "snapshots_list count=2" || bad "snapshots_list count"
echo "$out" | grep -q "PURGEABLE=" && ok "snapshots_list purgeable" || bad "snapshots_list purgeable"
export MOCK_SNAPS=0
out=$(snapshots_list)
echo "$out" | grep -q "SNAPSHOT_COUNT=0" && ok "snapshots_list handles none" || bad "snapshots_list none"
export MOCK_SNAPS=1 KAVIMAC_YES=1
out=$(snapshots_thin)
echo "$out" | grep -q "SNAPSHOTS_THINNED=1" && ok "snapshots_thin ok" || bad "snapshots_thin"
unset KAVIMAC_YES
out=$(disk_browser "$FAKEHOME")
echo "$out" | grep -q "DISK_BROWSER_PATH=$FAKEHOME" && ok "disk_browser path" || bad "disk_browser path"
out=$(disk_browser "/System/Library" 2>&1); rc=$?
check "disk_browser refuses /System" "1" "$rc"

echo "== startup.sh (list-only, non-interactive) =="
mkdir -p "$FAKEHOME/Library/LaunchAgents"
cat > "$FAKEHOME/Library/LaunchAgents/com.example.helper.plist" <<'EOF'
<?xml version="1.0"?><plist><dict><key>Label</key><string>com.example.helper</string></dict></plist>
EOF
out=$(startup_list </dev/null 2>&1)
echo "$out" | grep -q "STARTUP_ITEMS=" && ok "startup_list emits STARTUP_ITEMS" || bad "startup_list items"
echo "$out" | grep -qi "example" && ok "startup_list shows example agent" || bad "startup_list example"

echo "== uninstall.sh (find_orphans) =="
mkdir -p "$FAKEHOME/Applications" "$FAKEHOME/Library/Preferences"
echo "x" > "$FAKEHOME/Library/Preferences/com.deadapp.plist"
export KAVIMAC_YES=1
out=$(find_orphans 2>&1)
echo "$out" | grep -q "ORPHANS_FOUND=" && ok "find_orphans emits ORPHANS_FOUND" || bad "find_orphans found"
unset KAVIMAC_YES
out=$(uninstall_app "NoSuchAppXYZ" 2>&1); rc=$?
check "uninstall missing app rc" "1" "$rc"
echo "$out" | grep -q "APP_NOT_FOUND=1" && ok "uninstall APP_NOT_FOUND" || bad "uninstall not-found"
out=$(uninstall_app "BlueBubbles" 2>&1); rc=$?
check "uninstall blocked rc" "1" "$rc"

echo "== languages.sh / maintenance.sh =="
mkdir -p "$FAKEHOME/Applications/DemoApp.app/Contents/Resources/fr.lproj" \
         "$FAKEHOME/Applications/DemoApp.app/Contents/Resources/en.lproj"
echo "x" > "$FAKEHOME/Applications/DemoApp.app/Contents/Resources/fr.lproj/f"
echo "x" > "$FAKEHOME/Applications/DemoApp.app/Contents/Resources/en.lproj/f"
export KAVIMAC_YES=1
out=$(prune_languages 2>&1)
echo "$out" | grep -q "LANGUAGES_PRUNED=" && ok "prune_languages emits LANGUAGES_PRUNED" || bad "prune_languages"
[[ ! -e "$FAKEHOME/Applications/DemoApp.app/Contents/Resources/fr.lproj" ]] \
    && ok "prune removed fr.lproj" || bad "prune fr.lproj"
[[ -e "$FAKEHOME/Applications/DemoApp.app/Contents/Resources/en.lproj" ]] \
    && ok "prune kept en.lproj" || bad "prune en.lproj"
echo "$out" | grep -qi "disabled by design" && ok "arch-strip disclaimer" || bad "arch disclaimer"
unset KAVIMAC_YES
out=$(no_tty 'run_maintenance' 2>&1)
echo "$out" | grep -q "MAINTENANCE_DONE=1" && ok "run_maintenance completes on declines" || bad "run_maintenance"

echo "== optimize.sh (swap parsing regression) =="
# v1.0.0 bug: awk -F'[=,M]' '{print $3}' grabbed the word "used", crashing
# under set -u. The fixed parser must yield the numeric MB after "used =".
swap_probe=$(sysctl -n vm.swapusage | sed -n 's/.*used = \([0-9][0-9.]*\)M.*/\1/p' | cut -d. -f1)
check "swap parser yields MB number" "1536" "$swap_probe"
out=$(opt_memory_pressure 2>&1); rc=$?
check "opt_memory_pressure survives set -u" "0" "$rc"
echo "$out" | grep -q "Swap used: 1536 MB" && ok "opt_memory_pressure reports 1536 MB" || bad "opt_memory_pressure value"
echo "$out" | grep -q "WARNING" && bad "no warning under 2GB" || ok "no false heavy-swap warning"

echo "== services.sh =="
export MOCK_BB_UP=1
out=$(service_bluebubbles)
echo "$out" | grep -q "RUNNING" && ok "service_bluebubbles RUNNING" || bad "service bb"
echo "$out" | grep -q "uptime" && ok "service shows uptime" || bad "service uptime"
echo "$out" | grep -q "restarts since boot" && ok "service shows restarts" || bad "service restarts"
export MOCK_BB_UP=0
out=$(service_bluebubbles)
echo "$out" | grep -q "DOWN" && ok "service_bluebubbles DOWN" || bad "service bb down"
export MOCK_BB_UP=1

echo "== monitor: bb_autorestart (max 2 tries, no loop) =="
# shellcheck disable=SC1091
source "$REPO/kavimac-monitor.sh" 2>/dev/null || true
# (sourcing runs the monitor body; instead test the function directly in isolation)
rm -f "$TDIR/bb.state"
BB_STATE="$TDIR/bb.state" LOG="$TDIR/mon.log"
export MOCK_BB_UP=0
bb_autorestart 2>/dev/null || true
check "bb restart try 1 recorded" "1" "$(cat "$TDIR/bb.state")"
bb_autorestart 2>/dev/null || true
check "bb restart try 2 recorded" "2" "$(cat "$TDIR/bb.state")"
bb_autorestart 2>/dev/null || true
check "bb no 3rd try (exhausted)" "2" "$(cat "$TDIR/bb.state")"
export MOCK_BB_UP=1
bb_autorestart 2>/dev/null || true
check "bb counter resets on recovery" "0" "$(cat "$TDIR/bb.state")"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
rm -rf "$TDIR"
[[ "$FAIL" -eq 0 ]]
