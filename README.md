# notes-git-sync

A tiny launchd-driven sync loop that turns a plain folder of Markdown notes into a
**mergeable, self-owned sync chain**:

```
FSNotes Mac ──push/pull──┐
                         │
     bare remote (SSH) ◄─┼── push/pull ── FSNotes iOS (auto-pull)
                         │
                         └── push/pull ── Termux + Markor (Android)
```

Notes stay plain `.md` files in `~/Notes`. The only transport is git (over SSH to a
bare repo you own) — so concurrent edits from different devices are **3-way merged**,
collisions surface as visible conflict markers instead of silent overwrites, and the
full history of every note is preserved.

This repo contains the Mac-side background syncer:

| File | Purpose |
|---|---|
| `bin/notes-sync.sh` | commit (if changes) → fetch → **merge** `origin/main` → push; conflicts surface as markers *inside the note* and auto-push once you remove them |
| `launchd/co.roman.notes-sync.plist` | launchd agent template (cadence via `__INTERVAL__`) |
| `bin/notes-conflict-scan.sh` + hourly plist | janitor: notification if conflict markers linger in any note |
| `install.sh` | installs script + agent, `./install.sh [seconds]` (default 180) |
| `android/` | Android peer: Termux sync script + setup runbook (`android/setup.md`) |

## Requirements (one-time)

1. A server you control with SSH and `git`; a **bare** repo, e.g.
   `git init --bare -b main ~/repos/notes.git` under a dedicated `git` user whose shell is
   `git-shell` (key-only login, no interactive shell).
2. An SSH key authorized for that account: `~/.ssh/notes_git` on this Mac.
3. FSNotes (or any editor) with its storage pointed at `~/Notes`.

### Server hardening (once all peer keys are verified)

```bash
# on the server, as root:
cat > /etc/ssh/sshd_config.d/99-harden.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sshd -t && systemctl reload ssh   # validate BEFORE reload
```

After this:
- **root login: key only** — e.g. `ssh notesroot` (dedicated key + Host alias on the Mac)
- **passwords: disabled for every user** (git@ peers already use keys — unaffected)
- **lockout recovery:** the hosting panel's VNC console is out-of-band and ignores sshd;
  the root password keeps working there
- **back up the root key's private file** — losing it together with the Mac leaves only the console path

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
- **Merge strategy — never rebase**: on conflict the loop leaves `<<<<<<<` markers inside the
  note itself and notifies you (macOS notification / Termux:API). Remove the markers, keep
  the content you want — the next tick commits the resolution and pushes automatically.
  No silent stuck states: a conflict is always visible in the note or in a notification.
- **FSNotes users — important**: turn OFF FSNotes' own background git (scheduled snapshots
  and auto-pull). On a merge conflict FSNotes commits the marker-laden file and pushes it
  (commit message literally "Merge conflict"), poisoning the remote for all peers. Keep
  only its manual *Commit & Push* menu action; this launchd loop is the single background
  writer.
- **Leftover-marker guard**: an hourly scan (Mac launchd / Android cron) notifies if
  `<<<<<<<` / `>>>>>>>` markers linger in any note — e.g. after a partial manual resolution
  or a commit made while markers were present. Only those two line-starts are matched;
  a bare `=======` line is a valid Markdown heading underline and is never flagged.
- **Key security**: the private key (`~/.ssh/notes_git`) never leaves the Mac; the server
  account should be `git-shell`-locked and key-only.

## Failure taxonomy

| # | Name | What happens | What you do |
|---|---|---|---|
| 1 | **Content conflict** | Two peers edit the same lines within one sync window; the second integrator finds `<<<<<<<`/`>>>>>>>` markers *inside the note* + a notification | Reopen the note, keep the content you want, delete the three marker lines, save — auto-push follows within one tick |
| 2 | **Push race** | A clean merge loses its push to a peer that pushed mid-tick | Nothing; the next tick merges again (may become #1) |
| 3 | **Stale editor buffer** | The editor (FSNotes/Markor) still shows the pre-sync copy, so markers or new content look invisible | Close and reopen the note after any sync notification — the notifications say so |
| 4 | **Marker poison** | A file *with* markers gets committed and pushed, replicating to every peer. Seen from editor-integrated git (FSNotes background git — disabled in this setup) and from a space-in-filename bug in the marker detector (fixed: null-delimited `-z` iteration) | The hourly conflict scan flags it; remove the markers, commit — history keeps every side |
| 5 | **Corrupt object store (Android)** | Interrupted fetch on FUSE shared storage left an empty object file; every later fetch fails ("did not send all necessary objects") | Auto-cleaned by the script; the git DB now lives on ext4 (`~/.notes-git`), so this is structural history |
| 6 | **Hostile network** | Port 22 blocked or DNS broken (public Wi-Fi, some carriers); fetch fails | The notification carries the actual ssh reason; self-heals on the next good network; Tailscale is the fallback path |

### Network requirements

- Sync is plain SSH (port 22) to the bare repo over the public internet — works identically on
  home Wi-Fi, mobile data, and hotspots.
- Rare blockers: networks or carriers that filter outbound port 22 or break DNS. The fetch-failure
  notification carries the actual ssh/git reason, and sync self-heals on the next good network.
- Fallback for hostile networks: Tailscale (sync via the server's tailnet address; also restores
  remote administration of the phone from anywhere).

### Testing the chain (2-minute drill)

1. Edit the **same line** of one note on two devices within a 3-minute window.
2. Expect the second integrator to get `<<<<<<<` markers in the note + a MERGE CONFLICT notification.
3. Reopen the note in the editor, keep what you want, delete the three marker lines, save.
4. Within one tick: "conflict resolved — synced"; the other device converges on its next tick.
5. Edit *different* lines or notes on two devices → no conflict at all; git merges automatically.

## Peers

- **Mac**: FSNotes (storage = `~/Notes`, Git pane: hourly snapshots + Commit & Push menu)
- **iPhone**: FSNotes iOS → Preferences → Git (clone same repo, auto-pull automation on)
- **Android**: Termux (plain git, cron every 3 min, status notifications) + Markor — see `android/setup.md`. GitJournal is dead (no release since 2021); no maintained git-native notes app exists on Android.
