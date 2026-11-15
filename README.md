# notes-git-sync

A tiny launchd-driven sync loop that turns a plain folder of Markdown notes into a
**mergeable, self-owned sync chain**:

```
FSNotes Mac ──push/pull──┐
                         │
     bare remote (SSH) ◄─┼── push/pull ── FSNotes iOS (auto-pull)
                         │
                         └── push/pull ── GitJournal Android
```

Notes stay plain `.md` files in `~/Notes`. The only transport is git (over SSH to a
bare repo you own) — so concurrent edits from different devices are **3-way merged**,
collisions surface as visible conflict markers instead of silent overwrites, and the
full history of every note is preserved.

This repo contains the Mac-side background syncer:

| File | Purpose |
|---|---|
| `bin/notes-sync.sh` | commit (if changes) → fetch → rebase onto `origin/main` → push |
| `launchd/co.roman.notes-sync.plist` | launchd agent template (cadence via `__INTERVAL__`) |
| `install.sh` | installs script + agent, `./install.sh [seconds]` (default 180) |

## Requirements (one-time)

1. A server you control with SSH and `git`; a **bare** repo, e.g.
   `git init --bare -b main ~/repos/notes.git` under a dedicated `git` user whose shell is
   `git-shell` (key-only login, no interactive shell).
2. An SSH key authorized for that account: `~/.ssh/notes_git` on this Mac.
3. FSNotes (or any editor) with its storage pointed at `~/Notes`.

## Install

```bash
git clone https://github.com/romanakmath/notes-git-sync.git
cd notes-git-sync
./install.sh 180        # sync every 3 minutes
```

## Change the cadence

```bash
./install.sh 60         # every minute
./install.sh 300        # every 5 minutes
```

Verify: `launchctl list | grep notes-sync` (second column = last exit status, should be 0).

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/co.roman.notes-sync.plist
rm ~/Library/LaunchAgents/co.roman.notes-sync.plist ~/bin/notes-sync.sh
```

## Notes & caveats

- **FSNotes interplay**: FSNotes has its own hourly snapshot scheduler (clock-anchored,
  cannot go sub-hourly) and a per-note *Commit & Push* menu action. All three paths are
  safe together — worst case is a harmless one-off `index.lock` contention, retried next tick.
- **Sleep**: launchd doesn't tick while the Mac sleeps; missed runs coalesce into one run on wake.
- **Power**: a no-op tick costs ~0.1–0.5 s CPU and a few KB of SSH negotiation —
  at 3-minute cadence roughly 3–5 minutes of CPU *per day*, well under 1% battery.
- **Merge conflicts**: when two peers edit the same lines, `git rebase` stops and the loop
  exits to retry later — resolve the `<<<<<<<` markers in the note, commit, done.
- **Key security**: the private key (`~/.ssh/notes_git`) never leaves the Mac; the server
  account should be `git-shell`-locked and key-only.

## Peers

- **Mac**: FSNotes (storage = `~/Notes`, Git pane: hourly snapshots + Commit & Push menu)
- **iPhone**: FSNotes iOS → Preferences → Git (clone same repo, auto-pull automation on)
- **Android**: GitJournal → Custom repo, same URL, in-app generated SSH key
