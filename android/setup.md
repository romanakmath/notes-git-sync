# Android peer (Termux + Markor)

No git-native notes app survives on current Android (GitJournal: dead since 2021).
The phone therefore runs **plain git inside Termux** — the same
commit → fetch → rebase → push loop as the Mac launchd agent — and any editor
(Markor recommended) edits the plain `.md` files in shared storage.

```
Termux + Termux:API  — engine: holds the SSH key, runs notes-sync.sh every 3 min,
                       posts "synced HH:MM" / "STUCK: conflict" notifications
Markor               — editor over /storage/emulated/0/Notes
Termux:Widget        — optional "Sync-notes" home-screen button
```

## Install (F-Droid builds only — Play builds are deprecated and incompatible)

From F-Droid: **Termux**, **Termux:API**, **Termux:Widget**, **Termux:Boot**, and **Markor**.

## One-time setup in Termux

```bash
pkg update -y && pkg install -y git openssh cronie termux-services termux-api
ssh-keygen -t ed25519 -f ~/.ssh/notes_git -N "" -C "android-termux notes sync"
# authorize ~/.ssh/notes_git.pub in the server git account's authorized_keys
ssh-keyscan -t ed25519,rsa SERVER_HOST >> ~/.ssh/known_hosts
git config --global user.name  "your name"
git config --global user.email "you@example.com"
termux-setup-storage                       # tap Allow — grants shared storage
git clone ssh://git@SERVER_HOST/home/git/repos/notes.git ~/storage/shared/Notes
git config --global --add safe.directory /storage/emulated/0/Notes   # FUSE uid quirk
cd ~/storage/shared/Notes && git config core.fileMode false
mkdir -p ~/bin && install -m 755 termux-notes-sync.sh ~/bin/notes-sync.sh
```

## Automation

```bash
# cron every 3 minutes (supervised by runit: sv up crond)
( crontab -l 2>/dev/null; echo "*/3 * * * * bash \$HOME/bin/notes-sync.sh" ) | crontab -

# home-screen button for Termux:Widget
mkdir -p ~/.shortcuts
printf '#!/data/data/com.termux/files/usr/bin/bash\nbash $HOME/bin/notes-sync.sh\n' \
      > ~/.shortcuts/Sync-notes && chmod +x ~/.shortcuts/Sync-notes

# start after reboot (needs the Termux:Boot app, opened once)
mkdir -p ~/.termux/boot
printf '#!/data/data/com.termux/files/usr/bin/bash\npgrep -x sshd >/dev/null || sshd\nsv up crond 2>/dev/null; true\n' \
      > ~/.termux/boot/start-notes-sync.sh && chmod +x ~/.termux/boot/start-notes-sync.sh
```

## MIUI/Xiaomi survival (critical — do not skip)

Without these, MIUI kills Termux in the background and sync stops *silently*:

- Settings → Apps → Termux → Battery → **No restrictions** (also for Termux:API)
- Recent apps → pull the Termux card down → **lock** it (padlock icon)
- The "synced HH:MM" notifications are your heartbeat: if they stop, check Battery settings.

## Failure modes (all surfaced as notifications)

| Notification | Meaning |
|---|---|
| `synced HH:MM` | a change was committed and pushed |
| `fetch failed — no network?` | offline; retries next tick |
| `STUCK: merge conflict` | same lines edited on two peers — open Termux, resolve `<<<<<<<` in the note, commit |
| `push failed` | key rejected or network half-up |
