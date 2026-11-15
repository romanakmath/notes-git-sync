#!/bin/bash
# notes-git-sync — commit / pull --rebase / push loop for a plain-markdown vault
# Designed to run from launchd every few minutes. Exits silently on transient
# failures so the next tick retries; never deletes or overwrites remote history.
#
# Config (env overrides, sensible defaults for the standard install):
#   NOTES_DIR  vault folder           (default ~/Notes)
#   GIT_KEY    ssh private key        (default ~/.ssh/notes_git)

NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"
GIT_KEY="${GIT_KEY:-$HOME/.ssh/notes_git}"

export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

cd "$NOTES_DIR" || exit 0

# 1. commit local changes (FSNotes may also commit itself — both are fine)
git add -A
git diff --cached --quiet || git commit -q -m "autosync $(date '+%F %T')"

# 2. fetch and rebase onto remote (rebase refused mid-conflict -> abort, retry next tick)
git fetch origin -q || exit 0
if [ -n "$(git rev-list main..origin/main)" ]; then
  git rebase origin/main -q || { git rebase --abort 2>/dev/null; exit 0; }
fi

# 3. publish
git push -q
