#!/data/data/com.termux/files/usr/bin/bash
# notes-sync — Android/Termux variant (cron every 3 min, Termux:Widget shortcut)
# Strategy: MERGE, never rebase. Conflicts surface as markers inside the note;
# this script waits for the human to remove them (in Markor), then auto-pushes.
# Notifications: Termux:API (needs the Termux:API app).

NOTES_DIR="${NOTES_DIR:-$HOME/storage/shared/Notes}"
GIT_KEY="${GIT_KEY:-$HOME/.ssh/notes_git}"
export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

notify() { command -v termux-notification >/dev/null 2>&1 && termux-notification --title "Notes sync" --content "$1"; }

cd "$NOTES_DIR" || exit 0

# 1. A merge left waiting for human resolution? Finish it once markers are gone.
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  unresolved=""
  while IFS= read -r -d '' f; do
    grep -qE '^(<<<<<<<|>>>>>>>) ' "$f" 2>/dev/null && unresolved="$unresolved $f"
  done < <(git diff --name-only --diff-filter=U -z)
  if [ -n "$unresolved" ]; then
    notify "conflict markers still in:$unresolved — close+reopen the note in Markor, remove markers"
    exit 0
  fi
  git add -A && git commit -q --no-edit \
    && (git push -q || notify "resolved but push failed — retrying next tick") \
    && notify "conflict resolved — synced $(date +%H:%M)"
  exit 0
fi

# 2. Commit local changes
git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "autosync (android) $(date '+%F %T')"
fi

# guard: interrupted fetches can leave empty object files (seen on FUSE shared
# storage); they wedge every later fetch with "did not send all necessary objects"
find "$(git rev-parse --git-dir)/objects" -type f -empty -delete 2>/dev/null

# 3. Integrate remote: merge (fast-forward when clean, markers when not)
FETCH_ERR="${TMPDIR:-$HOME}/notes-fetch.err"
if ! git fetch origin -q 2>"$FETCH_ERR"; then
  reason=$(grep -m1 -E "ssh:|fatal:|Could not" "$FETCH_ERR" | cut -c1-70)
  notify "fetch failed: ${reason:-unknown — see $FETCH_ERR}"
  exit 0
fi
if [ -n "$(git rev-list main..origin/main)" ]; then
  if ! git merge --no-edit origin/main >/dev/null 2>&1; then
    notify "MERGE CONFLICT — close+reopen the note in Markor, remove <<<<<<< markers, save"
    exit 0
  fi
fi

# 4. Publish
git push -q || notify "push failed — retrying next tick"
exit 0
