#!/data/data/com.termux/files/usr/bin/bash
# notes-sync — Android/Termux variant of the Mac launchd loop
# Runs from cron (*/3) or the Termux:Widget "Sync-notes" shortcut.
NOTES_DIR="${NOTES_DIR:-$HOME/storage/shared/Notes}"
GIT_KEY="${GIT_KEY:-$HOME/.ssh/notes_git}"
export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

notify() { command -v termux-notification >/dev/null 2>&1 && termux-notification --title "Notes sync" --content "$1"; }

cd "$NOTES_DIR" || exit 0
changed=0
git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "autosync (android) $(date '+%F %T')" && changed=1
fi
if ! git fetch origin -q; then notify "fetch failed — no network?"; exit 0; fi
if [ -n "$(git rev-list main..origin/main)" ]; then
  git rebase origin/main -q || { git rebase --abort 2>/dev/null; notify "STUCK: merge conflict — open Termux"; exit 0; }
fi
if git push -q; then
  [ "$changed" = 1 ] && notify "synced $(date +%H:%M)"
else
  notify "push failed — check key/network"
fi
exit 0
