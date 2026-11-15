#!/bin/bash
# notes-conflict-scan — hourly guard: warn about leftover git conflict markers.
# Matches only '<<<<<<< ' / '>>>>>>> ' line starts; a bare '=======' line is a
# valid Markdown setext heading underline and is deliberately NOT flagged.
# Usage: notes-conflict-scan.sh [vault-dir]     (default: $NOTES_DIR or ~/Notes)

DIR="${1:-${NOTES_DIR:-$HOME/Notes}}"
cd "$DIR" || exit 0

hits=$(grep -rlE --include='*.md' --include='*.markdown' --include='*.txt' \
      --exclude-dir=.git '^(<<<<<<<|>>>>>>>) ' . 2>/dev/null | sed 's|^\./||')
[ -z "$hits" ] && exit 0

n=$(echo "$hits" | wc -l | tr -d ' ')
first=$(echo "$hits" | head -3 | tr '\n' ';')
echo "$(date '+%F %T')  conflict markers in $n file(s): $first"
osascript -e "display notification \"Conflict markers in $n file(s): $first — remove them to unblock sync\" with title \"Notes conflict scan\"" 2>/dev/null
exit 0
