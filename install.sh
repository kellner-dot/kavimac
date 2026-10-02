#!/bin/bash
#===============================================================================
# KaviGuard installer — installs to /opt/kaviguard, registers monitor LaunchAgent
#===============================================================================
set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/opt/kaviguard"
VERSION=$(cat "$SRC_DIR/VERSION")

echo "=== KaviGuard v$VERSION installer ==="

# Syntax check all scripts first
for f in "$SRC_DIR/kavimac.sh" "$SRC_DIR/kavimac-monitor.sh" "$SRC_DIR"/lib/*.sh; do
    bash -n "$f" || { echo "[FAIL] syntax error in $f"; exit 1; }
done
echo "[ok] all scripts syntax-checked"

# Install
sudo mkdir -p "$DEST"
sudo cp -R "$SRC_DIR/kavimac.sh" "$SRC_DIR/kavimac-monitor.sh" "$SRC_DIR/lib" "$DEST/"
sudo cp "$SRC_DIR/VERSION" "$DEST/"
sudo chmod +x "$DEST/kavimac.sh" "$DEST/kavimac-monitor.sh"
# Files must be runnable by the user (not just root) — the .app launcher runs as the user
sudo chown -R "$(id -un):staff" "$DEST"
sudo mkdir -p "$DEST/vpn"
echo "[ok] installed to $DEST"

# LaunchAgent for the monitor (user-level, no sudo needed for load)
# Retire the old com.seth.kavimac label if it's still around
launchctl unload "$HOME/Library/LaunchAgents/com.seth.kavimac.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.seth.kavimac.plist"
PLIST="$SRC_DIR/com.seth.kaviguard.plist"
# Fix the program path to the installed location
sed "s|/opt/kaviguard/kavimac-monitor.sh|$DEST/kavimac-monitor.sh|" "$PLIST" \
    > "$HOME/Library/LaunchAgents/com.seth.kaviguard.plist"
launchctl load "$HOME/Library/LaunchAgents/com.seth.kaviguard.plist" 2>/dev/null \
    && echo "[ok] monitor LaunchAgent loaded (every 15 min)" \
    || echo "[warn] LaunchAgent load had issues — check manually"

echo ""
echo "Done. Run: $DEST/kavimac.sh"
echo "Monitor log: /tmp/kavimac-monitor.log"
