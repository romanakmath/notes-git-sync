#!/bin/bash
# Install (or re-install) the notes-git-sync launchd agent.
#   usage: ./install.sh [interval-seconds]     # default 180
set -e
INTERVAL="${1:-180}"
DEST="$HOME/Library/LaunchAgents/co.roman.notes-sync.plist"

mkdir -p "$HOME/bin"
install -m 755 bin/notes-sync.sh "$HOME/bin/notes-sync.sh"
sed -e "s|__HOME__|$HOME|g" -e "s|__INTERVAL__|$INTERVAL|g" \
    launchd/co.roman.notes-sync.plist > "$DEST"

launchctl unload "$DEST" 2>/dev/null || true
launchctl load "$DEST"
echo "installed: $DEST"
echo "cadence: every ${INTERVAL}s — verify with: launchctl list | grep notes-sync"
