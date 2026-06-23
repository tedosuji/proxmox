# Windrose Server — Operator Runbook

How to actually *apply* changes to the Windrose dedicated server (VM 119). This is the
"if Claude is down, here's how to do it by hand" reference. For *what* the difficulty
knobs mean and their value ranges, see [`windrose-customization.md`](./windrose-customization.md).

> **Secrets:** server name, join password, and invite code are NOT in this repo (it's
> public). They live in the gitignored `windrose-server-*` files and in the private home
> wiki (`wiki.home` → Services → Windrose). Pull them from there when you need them.

---

## Access

VM 119 is a **Windows 11 VM** (not an LXC), reached over SSH:

```bash
ssh potat@192.168.68.67
```

**Gotcha — the VM's default SSH shell is PowerShell.** A nested
`powershell -Command "...$x..."` gets mangled (the outer shell eats `$vars` and quotes).
For anything with `$` or quotes, encode the script instead:

```bash
# build the script locally, then:
ENC=$(python3 -c "import base64; print(base64.b64encode(open('script.ps1').read().encode('utf-16-le')).decode())")
ssh potat@192.168.68.67 "powershell -NoProfile -EncodedCommand $ENC"
```

Simple commands with no `$`/quotes (or `cmd /c ...`) run fine inline.

---

## Key paths on the VM

| What | Path |
|---|---|
| Install root | `C:\Game_Servers\Windrose_Server` |
| **Server settings** (name/password/players/region/port) | `…\R5\ServerDescription.json` |
| **World settings** (difficulty/scaling) | `…\R5\Saved\SaveProfiles\Default\RocksDB_v2\0.10.0\Worlds\C688858D99A741262A8BF02919ABA1DA\WorldDescription.json` |
| World updater tool | `…\R5WorldDescriptionUpdater.exe` |
| World save DB (do not edit/delete) | `…\R5\Saved\SaveProfiles\Default\RocksDB_v2` |
| Server log (current) | `…\R5\Saved\Logs\R5.log` |
| Backup script log | `C:\ProgramData\windrose-backup\backup.log` |

> The world `SaveProfiles\Default\` segment was added by a game update (~June 2026). If a
> path 404s, re-find it: `ssh potat@192.168.68.67 'cmd /c dir /s /b C:\Game_Servers\Windrose_Server\R5\Saved\WorldDescription.json'`.
> The island id `C688…A1DA` is the live world — **never** change `WorldIslandId` (it
> switches which world loads and looks like all progress vanished).

| Item | Value |
|---|---|
| Game port | **7777** (TCP + UDP), direct-connect, password-protected, 6 players |
| Server process | `WindroseServer-Win64-Shipping.exe` (runs as SYSTEM, Session 0) |
| Auto-start | Scheduled Task `WindroseServer` (at boot) |
| Nightly save backup | Scheduled Task `WindroseSaveBackup` → `\\192.168.68.58\scott\windrose-backups` |

---

## Start / stop / restart

```bash
# Start (runs the boot task as SYSTEM)
ssh potat@192.168.68.67 'schtasks /Run /TN WindroseServer'

# Stop (end the task, then kill the process)
ssh potat@192.168.68.67 'cmd /c "schtasks /End /TN WindroseServer & taskkill /F /IM WindroseServer-Win64-Shipping.exe"'

# Verify it's up and listening (give UE5 ~30s to boot after a start)
ssh potat@192.168.68.67 'powershell -NoProfile -Command Get-Process WindroseServer-Win64-Shipping; Get-NetTCPConnection -LocalPort 7777 -State Listen'
```

A restart is a ~1 minute blip. World progress lives in the RocksDB database (separate from
the JSON config), so it survives restarts; anyone online just reconnects.

---

## Run a manual save backup

The nightly task also works on demand. It **stops the server, zips the saves, copies them to
the Samba share, then restarts the server** — so the server is running again when it finishes.

```bash
ssh potat@192.168.68.67 'schtasks /Run /TN WindroseSaveBackup'
# confirm success (LastTaskResult should be 0):
ssh potat@192.168.68.67 'powershell -NoProfile -Command Get-ScheduledTaskInfo -TaskName WindroseSaveBackup | Format-List TaskName,LastTaskResult,LastRunTime'
ssh potat@192.168.68.67 'powershell -NoProfile -Command Get-Content C:\ProgramData\windrose-backup\backup.log -Tail 8'
```

> Run it **as the scheduled task**, not `backup-saves.ps1` directly over SSH — the Samba
> credential is DPAPI-encrypted under SYSTEM, so an interactive run as `potat` fails with
> "Key not valid for use in specified state".

---

## Procedure A — change difficulty / world settings

This is the main one (e.g. "put it in easy mode" / "back to normal"). Follow every step.

1. **Backup first** — run the manual backup above and confirm `LastTaskResult 0`.
   (Remember: the backup leaves the server *running*, so you still stop it next.)
2. **Stop the server** (stop command above). Confirm the process is gone:
   `ssh potat@192.168.68.67 'cmd /c tasklist | findstr /I windrose'` (no output = stopped).
3. **Edit `WorldDescription.json`** (path in the table above) **while stopped**. Use surgical
   string replacements — don't reserialize the JSON (preserves the `CreationTime` float and
   the escaped `{\"TagName\": …}` keys). The values to touch are below.
4. **Apply to the existing world** — run the updater (it patches the JSON into the world's
   `_Latest.zip` so the live world picks it up):
   ```bash
   ssh potat@192.168.68.67 'powershell -NoProfile -Command Start-Process C:\Game_Servers\Windrose_Server\R5WorldDescriptionUpdater.exe -ArgumentList \"<full path to WorldDescription.json>\" -NoNewWindow -Wait'
   ```
   Expect `updater_exit=0` and a "Successfully added … WorldDescription.json … to … _Latest.zip" line.
5. **Restart** (start command above) and **verify** it's listening on 7777.

### The values that live in `WorldDescription.json`

These sit inside `WorldSettings`. As soon as any custom value is set, `WorldPresetType`
shows `Custom` (that's just the label — the values below are what actually drive difficulty;
leave it `Custom`).

| Key in JSON | Easy mode | Normal mode | Notes |
|---|---|---|---|
| `…CombatDifficulty` TagName | `…CombatDifficulty.Easy` | `…CombatDifficulty.Normal` | also `.Hard` |
| `…EasyExplore` (bool) | `true` | `false` | true = map markers ON (name is backwards) |
| `…MobHealthMultiplier` | `0.5` | `1` | enemy health |
| `…MobDamageMultiplier` | `0.5` | `1` | enemy damage |
| `…BoardingDifficultyMultiplier` | `0.5` | `1` | boarding fights |
| `…ShipsHealthMultiplier` | `1` | `1` | not touched by easy/normal |
| `…ShipsDamageMultiplier` | `1` | `1` | not touched by easy/normal |

"**Easy mode**" and "**normal mode**" are the two presets we toggle between; the rows above
are the exact values for each. For the full range of each knob, see `windrose-customization.md`.

---

## Procedure B — change server settings (name / password / players / region)

Same shape, simpler: these live in `…\R5\ServerDescription.json`.

1. Backup, 2. stop, 3. edit `ServerDescription.json` while stopped, 4. restart + verify.
   (No updater step — `ServerDescription.json` is read fresh on start.)

Editable fields: `ServerName`, `Password` / `IsPasswordProtected`, `InviteCode`,
`MaxPlayerCount`, `UserSelectedRegion` (`EU`/`SEA`/`CIS`/blank=auto), `DirectConnectionServerPort`.
**If you change the name/password/invite, also update the gitignored `windrose-server-*`
files and the wiki page.** Never change `WorldIslandId`.

---

## Safety notes

- Edit JSON **only while the server is stopped** — never live.
- The game autosaves every ~10 min into `RocksDB_v2_Backups` (+ `_Latest`), and
  `AutoLoadLatestBackupIfHasBroken=true` self-heals a broken DB.
- Prefer a low-activity moment — a stop disconnects active players. Check first:
  `ssh potat@192.168.68.67 'powershell -NoProfile -Command (Get-NetTCPConnection -LocalPort 7777 -State Established).Count'`
- VM 119 is **excluded from Proxmox vzdump** (120 GB Windows disk). The world saves are
  protected by the nightly `WindroseSaveBackup` task instead — that's the backup that matters.
