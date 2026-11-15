#!/bin/bash
# notes-sync — commit / merge / push loop for the Mac vault (launchd, every 3 min)
# Strategy: MERGE, never rebase. Conflicts surface as markers inside the note;
# this script waits for the human to remove them, then auto-commits and pushes.
# Notifications: macOS notification center (osascript).

NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"
GIT_KEY="${GIT_KEY:-$HOME/.ssh/notes_git}"
export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

say() { osascript -e "display notification \"$1\" with title \"Notes sync\"" 2>/dev/null; }

cd "$NOTES_DIR" || exit 0

# 1. A merge left waiting for human resolution? Finish it once markers are gone.
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  unresolved=""
  for f in $(git diff --name-only --diff-filter=U); do
    grep -qE '^(<<<<<<<|>>>>>>>) ' "$f" 2>/dev/null && unresolved="$unresolved $f"
  done
  if [ -n "$unresolved" ]; then
    say "conflict markers still in:$unresolved — remove them, auto-push follows"
    exit 0
  fi
  git add -A && git commit -q --no-edit && git push -q \
    && say "conflict resolved — synced $(date +%H:%M)"
  exit 0
fi

# 2. Commit local changes (FSNotes/other editors write plain files)
git add -A
git diff --cached --quiet || git commit -q -m "autosync $(date '+%F %T')"

# 3. Integrate remote: merge (fast-forward when clean, markers when not)
git fetch origin -q || { say "fetch failed — offline?"; exit 0; }
if [ -n "$(git rev-list main..origin/main)" ]; then
  if ! git merge --no-edit origin/main >/dev/null 2>&1; then
    say "MERGE CONFLICT — open the marked note(s), remove markers; auto-push follows"
    exit 0
  fi
fi

# 4. Publish
git push -q
exit 0
