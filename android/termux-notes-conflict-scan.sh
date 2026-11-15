#!/data/data/com.termux/files/usr/bin/bash
# notes-conflict-scan — Android guard: warn about leftover git conflict markers.
# Matches only '<<<<<<< ' / '>>>>>>> ' line starts; a bare '=======' line is a
# valid Markdown setext heading underline and is deliberately NOT flagged.
# Usage: notes-conflict-scan.sh [vault-dir]   (default: $NOTES_DIR or the vault)

DIR="${1:-${NOTES_DIR:-$HOME/storage/shared/Notes}}"
cd "$DIR" || exit 0

notify() { command -v termux-notification >/dev/null 2>&1 && termux-notification --title "Notes conflict scan" --content "$1"; }

hits=$(grep -rlE --include='*.md' --include='*.markdown' --include='*.txt' \
      --exclude-dir=.git '^(<<<<<<<|>>>>>>>) ' . 2>/dev/null | sed 's|^\./||')
[ -z "$hits" ] && exit 0

n=$(echo "$hits" | wc -l | tr -d ' ')
first=$(echo "$hits" | head -3 | tr '\n' ';')
echo "$(date '+%F %T')  conflict markers in $n file(s): $first"
notify "Conflict markers in $n file(s): $first — remove them in Markor"
exit 0
