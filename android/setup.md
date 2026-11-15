# Android peer (Termux + Markor)

No git-native notes app survives on current Android (GitJournal: dead since 2021,
its niche never refilled). The phone therefore runs **plain git inside Termux** —
the same commit → fetch → **merge** → push loop as the Mac launchd agent — while any
editor edits the plain `.md` files in shared storage. Conflicts appear as markers
inside the note; remove them in Markor and the next tick auto-pushes.

## 0. The five apps (all from F-Droid — Play builds are deprecated & signature-incompatible)

| App | Role | Required? |
|---|---|---|
| **Termux** | the engine: git, SSH key, sync script, cron | ✅ yes |
| **Termux:API** | makes `termux-notification` work → the "synced HH:MM" heartbeat | strongly recommended |
| **Termux:Boot** | starts sshd + crond after phone reboot | recommended |
| **Termux:Widget** | "Sync-notes" button on the home screen | optional |
| **Markor** | the notes editor (any plain-markdown editor works) | one editor of choice |

> ⚠️ All Termux add-ons must come from the **same source** as Termux itself
> (F-Droid ↔ F-Droid). Mixed sources fail signature verification.
> Uninstalling Termux wipes its entire world — keys, cron, scripts — by design.

## 1. One-time setup in Termux

```bash
pkg update -y && pkg install -y git openssh cronie termux-services termux-api
ssh-keygen -t ed25519 -f ~/.ssh/notes_git -N "" -C "android-termux notes sync"
# authorize ~/.ssh/notes_git.pub in the server git account's authorized_keys
ssh-keyscan -t ed25519,rsa SERVER_HOST >> ~/.ssh/known_hosts
git config --global user.name  "your name"
git config --global user.email "you@example.com"
termux-setup-storage                       # tap Allow — grants shared storage
# Clone, then relocate the git DB to Termux-internal (ext4) storage: notes stay
# on shared storage (for Markor), while .git — the database fetch writes into —
# lives on a real filesystem. Interrupted fetches on FUSE shared storage
# otherwise leave EMPTY object files that wedge every future fetch
# ("... did not send all necessary objects").
git clone ssh://git@SERVER_HOST/home/git/repos/notes.git ~/vault-tmp
mv ~/vault-tmp/.git ~/.notes-git
git --git-dir=$HOME/.notes-git config core.worktree /storage/emulated/0/Notes
mkdir -p ~/storage/shared/Notes && mv ~/vault-tmp/* ~/storage/shared/Notes/ && rmdir ~/vault-tmp
echo "gitdir: /data/data/com.termux/files/home/.notes-git" > ~/storage/shared/Notes/.git
git config --global --add safe.directory /storage/emulated/0/Notes   # FUSE uid quirk
cd ~/storage/shared/Notes && git config core.fileMode false
mkdir -p ~/bin && install -m 755 termux-notes-sync.sh ~/bin/notes-sync.sh
```

## 2. Automation

```bash
# cron every 3 minutes (supervised by runit: sv up crond)
( crontab -l 2>/dev/null; echo "*/3 * * * * bash \$HOME/bin/notes-sync.sh" ) | crontab -

# hourly guard against leftover conflict markers
install -m 755 termux-notes-conflict-scan.sh ~/bin/notes-conflict-scan.sh
( crontab -l 2>/dev/null; echo "0 * * * * bash \$HOME/bin/notes-conflict-scan.sh" ) | crontab -

# home-screen button for Termux:Widget
mkdir -p ~/.shortcuts
printf '#!/data/data/com.termux/files/usr/bin/bash\nbash $HOME/bin/notes-sync.sh\n' \
      > ~/.shortcuts/Sync-notes && chmod +x ~/.shortcuts/Sync-notes

# start after reboot (needs the Termux:Boot app, opened once)
mkdir -p ~/.termux/boot
printf '#!/data/data/com.termux/files/usr/bin/bash\npgrep -x sshd >/dev/null || sshd\nsv up crond 2>/dev/null; true\n' \
      > ~/.termux/boot/start-notes-sync.sh && chmod +x ~/.termux/boot/start-notes-sync.sh
```

## 3. MIUI/Xiaomi survival (critical — do not skip)

Without these, MIUI kills Termux in the background and sync stops *silently*:

- Settings → Apps → Termux → Battery → **No restrictions** (also for Termux:API)
- Recent apps → pull the Termux card down → **lock** it (padlock icon)
- The "synced HH:MM" notifications are your heartbeat: if they stop, check Battery settings.

## 4. Point the editor at the vault

Markor → open folder → internal storage → `Notes` (`/storage/emulated/0/Notes`).

## 5. Verify it works

1. Edit any note in Markor, save.
2. Within ≤ 3 minutes a "Notes sync: synced HH:MM" notification appears.
3. On the Mac: `git -C ~/Notes log --oneline -1` shows `autosync (android) …`.

## Failure modes (all surfaced as notifications)

| Notification | Meaning |
|---|---|
| `synced HH:MM` | a change was committed and pushed |
| `fetch failed — no network?` | offline; retries next tick |
| `STUCK: merge conflict` | same lines edited on two peers — open Termux, resolve `<<<<<<<` in the note, commit |
| `push failed` | key rejected or network half-up |
| `fetch failed: ... empty` / `did not send all necessary objects` | interrupted fetch left an empty object file — the sync script now auto-deletes these; manually: `find $(git rev-parse --git-dir)/objects -type f -empty -delete` |

## Remote administration (optional)

Termux can run `sshd` (port 8022) so a trusted machine can drive the phone over
SSH — handy for setup and maintenance. Put the admin machine's **public** key in
`~/.ssh/authorized_keys`, then `ssh -p 8022 <user>@<phone-ip>`. Over Tailscale
this works from anywhere; otherwise same Wi-Fi only.
