#!/bin/bash
#===============================================================================
# KaviMac installer — installs to /opt/kavimac, registers monitor LaunchAgent
#===============================================================================
set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/opt/kavimac"
VERSION=$(cat "$SRC_DIR/VERSION")

echo "=== KaviMac v$VERSION installer ==="

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
sudo mkdir -p "$DEST/vpn"
echo "[ok] installed to $DEST"

# LaunchAgent for the monitor (user-level, no sudo needed for load)
PLIST="$SRC_DIR/com.seth.kavimac.plist"
# Fix the program path to the installed location
sed "s|/opt/kavimac/kavimac-monitor.sh|$DEST/kavimac-monitor.sh|" "$PLIST" \
    > "$HOME/Library/LaunchAgents/com.seth.kavimac.plist"
launchctl load "$HOME/Library/LaunchAgents/com.seth.kavimac.plist" 2>/dev/null \
    && echo "[ok] monitor LaunchAgent loaded (every 15 min)" \
    || echo "[warn] LaunchAgent load had issues — check manually"

echo ""
echo "Done. Run: $DEST/kavimac.sh"
echo "Monitor log: /tmp/kavimac-monitor.log"
