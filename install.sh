#!/bin/bash
# Install (or re-install) the notes-git-sync launchd agents:
#   1. co.roman.notes-sync        — sync loop, every [interval-seconds] (default 180)
#   2. co.roman.notes-conflict-scan — leftover-marker guard, hourly
#   usage: ./install.sh [interval-seconds]
set -e
INTERVAL="${1:-180}"
DEST_SYNC="$HOME/Library/LaunchAgents/co.roman.notes-sync.plist"
DEST_SCAN="$HOME/Library/LaunchAgents/co.roman.notes-conflict-scan.plist"

mkdir -p "$HOME/bin"
install -m 755 bin/notes-sync.sh "$HOME/bin/notes-sync.sh"
install -m 755 bin/notes-conflict-scan.sh "$HOME/bin/notes-conflict-scan.sh"

sed -e "s|__HOME__|$HOME|g" -e "s|__INTERVAL__|$INTERVAL|g" \
    launchd/co.roman.notes-sync.plist > "$DEST_SYNC"
sed -e "s|__HOME__|$HOME|g" \
    launchd/co.roman.notes-conflict-scan.plist > "$DEST_SCAN"

for f in "$DEST_SCAN" "$DEST_SYNC"; do
  launchctl unload "$f" 2>/dev/null || true
  launchctl load "$f"
done
echo "installed:"
echo "  $DEST_SYNC (every ${INTERVAL}s)"
echo "  $DEST_SCAN (hourly)"
echo "verify: launchctl list | grep notes"
