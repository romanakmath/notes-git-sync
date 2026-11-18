#!/bin/bash
# notes-sync — commit / merge / push loop for the Mac vault (launchd, every 3 min)
# Strategy: MERGE, never rebase. Conflicts surface as markers inside the note;
# this script waits for the human to remove them, then auto-commits and pushes.
# Notifications: macOS notification center (osascript).

# Notes sync – Mac variant: dual-path (public URL first, tailnet IP fallback)
NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"
GIT_KEY="${GIT_KEY:-$HOME/.ssh/notes_git}"
# Private settings: env vars win; otherwise source ~/.config/notes-sync.conf
# (never committed — copy from notes-sync.conf.example). No hardcoded default.
NOTES_SYNC_CONF="${NOTES_SYNC_CONF:-$HOME/.config/notes-sync.conf}"
[ -r "$NOTES_SYNC_CONF" ] && . "$NOTES_SYNC_CONF"
export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

say() { osascript -e "display notification \"$1\" with title \"Notes sync\"" 2>/dev/null; }

if [ -z "${TAILNET_URL:-}" ]; then
  echo "notes-sync: TAILNET_URL is not set — put it in $NOTES_SYNC_CONF or the environment" >&2
  say "TAILNET_URL missing — create ~/.config/notes-sync.conf"
  exit 1
fi

fetch_all() {
  # primary: public hostname; fallback: tailnet IP (updates the same tracking ref)
  git fetch origin -q 2>/tmp/notes-fetch.err && return 0
  git fetch "$TAILNET_URL" +refs/heads/main:refs/remotes/origin/main -q 2>>/tmp/notes-fetch.err && return 0
  return 1
}

push_all() {
  git push -q && return 0
  git push -q "$TAILNET_URL" main && return 0
  return 1
}

cd "$NOTES_DIR" || exit 0

# 1. A merge left waiting for human resolution? Finish it once markers are gone.
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  unresolved=""
  while IFS= read -r -d '' f; do
    grep -qE '^(<<<<<<<|>>>>>>>) ' "$f" 2>/dev/null && unresolved="$unresolved $f"
  done < <(git diff --name-only --diff-filter=U -z)
  if [ -n "$unresolved" ]; then
    say "conflict markers still in:$unresolved — reopen the note in FSNotes, remove markers"
    exit 0
  fi
  git add -A && git commit -q --no-edit \
    && (push_all || say "resolved but push failed — retrying next tick") \
    && say "conflict resolved — synced $(date +%H:%M)"
  exit 0
fi

# 2. Commit local changes (FSNotes/other editors write plain files)
git add -A
git diff --cached --quiet || git commit -q -m "autosync $(date '+%F %T')"

# 3. Integrate remote: merge (fast-forward when clean, markers when not)
if ! fetch_all; then
  reason=$(grep -m1 -E "ssh:|fatal:|Could not" /tmp/notes-fetch.err | cut -c1-70)
  say "fetch failed (public + tailnet): ${reason:-see /tmp/notes-fetch.err}"
  exit 0
fi
if [ -n "$(git rev-list main..origin/main)" ]; then
  if ! git merge --no-edit origin/main >/dev/null 2>&1; then
    say "MERGE CONFLICT — reopen the note in FSNotes, remove <<<<<<< markers, save"
    exit 0
  fi
fi

# 4. Publish
push_all || say "push failed — retrying next tick"
exit 0
