#!/data/data/com.termux/files/usr/bin/bash
# notes-sync — Android/Termux variant (cron every 3 min, Termux:Widget shortcut)
# Strategy: MERGE, never rebase. Conflicts surface as markers inside the note;
# this script waits for the human to remove them (in Markor), then auto-pushes.
# Notifications: Termux:API (needs the Termux:API app).
# Dual-path: public URL first; on failure (hostile DNS/network) fall back to the
# server's Tailscale address — no DNS needed, works whenever Tailscale is up.

NOTES_DIR="${NOTES_DIR:-$HOME/storage/shared/Notes}"
GIT_KEY="${GIT_KEY:-$HOME/.ssh/notes_git}"
TAILNET_URL="${TAILNET_URL:-ssh://git@100.124.167.1/home/git/repos/notes.git}"
export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

notify() { command -v termux-notification >/dev/null 2>&1 && termux-notification --title "Notes sync" --content "$1"; }

cd "$NOTES_DIR" || exit 0

fetch_all() {
  # primary: public hostname; fallback: tailnet IP (updates the same tracking ref)
  git fetch origin -q 2>"$FETCH_ERR" && return 0
  if git fetch "$TAILNET_URL" +refs/heads/main:refs/remotes/origin/main -q 2>>"$FETCH_ERR"; then
    echo "$(date '+%F %T') public fetch failed, tailnet fallback OK" >> "${TMPDIR:-$HOME}/notes-fallback.log"
    tail -100 "${TMPDIR:-$HOME}/notes-fallback.log" >/dev/null 2>&1 # keep it bounded
    return 0
  fi
  return 1
}

push_all() {
  git push -q && return 0
  git push -q "$TAILNET_URL" main && return 0
  return 1
}

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
    && (push_all || notify "resolved but push failed — retrying next tick") \
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
if ! fetch_all; then
  reason=$(grep -m1 -E "ssh:|fatal:|Could not" "$FETCH_ERR" | cut -c1-70)
  notify "fetch failed (public + tailnet): ${reason:-unknown — see $FETCH_ERR}"
  exit 0
fi
if [ -n "$(git rev-list main..origin/main)" ]; then
  if ! git merge --no-edit origin/main >/dev/null 2>&1; then
    notify "MERGE CONFLICT — close+reopen the note in Markor, remove <<<<<<< markers, save"
    exit 0
  fi
fi

# 4. Publish
push_all || notify "push failed — retrying next tick"
exit 0
