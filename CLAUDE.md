# Proxmox Homelab

## Access
- Proxmox host: `ssh root@192.168.68.200`
- Web UI: https://192.168.68.200:8006

## Network
- Subnet: 192.168.68.0/22 (NOT /24 — Deco router uses /22)
- Gateway: 192.168.68.1 (TP-Link Deco mesh)
- DNS: Pi-hole at 192.168.68.51 (LXC 110)
- **CRITICAL**: LXC containers MUST use `ip=dhcp` — static IPs break networking (Deco has ARP protection/IP-MAC binding that drops traffic from IPs it didn't assign). Reserve IPs in the Deco app instead — let the device pull DHCP first so the Deco detects it, then reserve from the connected-clients list (don't manually enter the MAC).

## Containers
| VMID | Name | IP | Role |
|------|------|-----|------|
| 110 | pihole | .51 | DNS/Ad-block |
| 111 | samba | .58 | File Server |
| 112 | gotify | .59 | Push Notifications |
| 113 | bookstack | .52 | Wiki |
| 114 | proxy | .53 | Nginx Reverse Proxy |
| 115 | webapps | .55 | Static Web Apps |
| 116 | capitol-gains | .61 | Stock Trade Tracker (Docker) |
| 117 | cs2 | .60 | CS2 Dedicated Server (**public** branch) — **active** again; admin via CounterStrikeSharp |
| 118 | inventree | .64 | Parts Inventory (leverless controller business) |
| 119 | windrose | .67 | Windrose Dedicated Server (**Windows 11 VM**, not LXC) |
| 121 | palworld | .54 | Palworld Dedicated Server (**public** for friends) — LXC, native Linux/SteamCMD |

## Windows VM (119, Windrose game server)
- **QEMU/KVM VM, not an LXC.** Win 11 Home. Manage over **SSH** (`ssh potat@192.168.68.67`, PowerShell) or Proxmox noVNC console. No RDP (Home can't host it).
- **CPU must be a named model, NOT `host`** — `cpu: host` BSODs Win 11 24H2/25H2 setup (`PAGE_FAULT_IN_NONPAGED_AREA`, fbwf.sys). Using `x86-64-v3` (host is Intel i9-10900X, has AVX2).
- **q35 + OVMF + TPM 2.0 + Secure Boot** (Win 11 requirement). Disk on `local-lvm` (SSD), VirtIO SCSI.
- **Install gotchas**: use E1000 NIC during install/OOBE (Win has no built-in VirtIO NIC driver → no internet for the MS-account step), then install virtio-win guest tools and swap NIC to VirtIO. Load `vioscsi\w11\amd64` driver at the disk-select screen.
- **Windrose server**: SteamCMD app `4129620`, `login anonymous` (no account needed). Installed to `C:\Game_Servers\Windrose_Server`. First SteamCMD run only self-updates (exit 7) — **run it twice**. UE5 needs the bundled **VC++ redist** (`Engine\Extras\Redist\en-us\vc_redist.x64.exe`) or the exe dies with `0xC0000135` and no log.
- Config: `R5\ServerDescription.json` (edit only while stopped). Direct-connect on **7777 TCP+UDP**, password-protected, 6 players. Server name/password/invite-code kept in gitignored `windrose-*` files.
- **Operator runbook** (how to actually apply changes — backup, stop/start, edit + updater, exact paths/values): [`windrose-runbook.md`](./windrose-runbook.md). World settings now live under `…\R5\Saved\SaveProfiles\Default\RocksDB_v2\…\WorldDescription.json` (the `SaveProfiles\Default` segment was added by a ~June 2026 update). Difficulty toggles between **easy mode** and **normal mode** (exact values in the runbook).
- Auto-start: Scheduled Task `WindroseServer` (SYSTEM, at boot). Nightly save backup task `WindroseSaveBackup` → `//192.168.68.58/scott/windrose-backups`. SSH firewall scoped to `192.168.68.0/22`; only 7777 open inbound.
- **Player dashboard** at `windrose.home` (LAN-only): live crew + server settings + **all-time crew log** (visits & total playtime per player). Parser `C:\ProgramData\windrose-web\parse-players.ps1` on the VM reads all `R5.log` files (current + rotated backups) + the JSON configs → JSON; webapps LXC 115 pulls it every 60s via a **restricted forced-command SSH key** (`/root/.ssh/windrose_pull`, locked to only run the parser) → `/var/www/windrose`, fronted by proxy 114 + Pi-hole `windrose.home`→.53.
- **All-time stats**: a *visit* = a connection that reached `Join succeeded` (failed/rejected attempts never reach it, so no inflation), deduped by the per-connection `BLPlayerSessionId`. Identity = the 32-hex account GUID suffix of the BL `Name=`/`UniqueId` value (no SteamID64 exists — server is anonymous/Steam OSS off). Playtime pairs each join with its `UNetConnection::Close` (by port, then account). Counts persist across log rotation in `C:\ProgramData\windrose-web\player-stats.json` (keyed by GUID, with a `sessions` map for idempotent dedup); the parser merges new sessions each run. Backup of the pre-tracking parser: `parse-players.ps1.bak`.

## Palworld server (LXC 121, .54)
- **Native Linux** dedicated server (unlike Windrose) — plain **unprivileged LXC** (Debian 13), *not* a Windows VM. systemd unit `palworld.service` (user `steam`), install at `/home/steam/palworld`. Restart with `systemctl restart palworld` (or `service palworld restart`).
- **SteamCMD app `2394010`**, `login anonymous` (free). Like Windrose, the **first SteamCMD run only self-updates** (fails with `Missing configuration`) — **run it twice**. ~5 GB download / ~4.9 GB installed.
- **steamclient.so symlink required**: `~steam/.steam/sdk64/steamclient.so` → `~steam/steamcmd/linux64/steamclient.so`, or the server won't initialize.
- **Public for friends**: friends direct-connect to **WAN-IP : 8211/UDP** (no community-browser listing → `PublicIP` left blank). Needs a **Deco port-forward `8211/UDP` → .54**. **Password-protected** (`ServerPassword`); **no RCON** (`RCONEnabled=False`).
- **Config**: `Pal/Saved/Config/LinuxServer/PalWorldSettings.ini` — **edit only while stopped**. It's one giant `OptionSettings=(...)` line; seed it from `DefaultPalWorldSettings.ini` (in the install root) and edit keys. Currently: `ServerName`, `ServerPlayerMaxNum=16`, `ServerPassword`, `AdminPassword`, `PublicPort=8211`. **Server name/password/admin password kept in gitignored `palworld-pass`** (never in tracked docs).
- **Launch flags**: `-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS`. The unit's **`ExecStartPre` auto-updates on every start** (`app_update 2394010`) so friends' auto-updating clients always match the server version. CPU-wise Palworld is **single-thread-bound** — the host i9-10900X's high clock suits it.
- **Memory leak** (Palworld climbs over long sessions): a **root cron 05:00** runs `/root/palworld-nightly.sh` → tars `Pal/Saved/SaveGames` to **`//192.168.68.58/scott/palworld-backups`** (via `smbclient` + root-only `/root/.smbcreds`; **userspace SMB, no kernel CIFS mount** since the LXC is unprivileged; keeps last 14) **then restarts** the server. Idle RSS ≈ 950 MB; cgroup cap **8 GB**.
- **RAM caution**: the 8 GB cap coexists with CS2 (8 GB) + Windrose VM (~7 GB live) on a **32 GB host** — fine idle / small crew, but watch for swap if all three are loaded simultaneously. Host-RAM upgrade is the real fix (on hold).
- **Backups**: excluded from vzdump (game is re-downloadable); only `Pal/Saved/SaveGames` is backed up (nightly, above).

## CS2 server (LXC 117, .60)
- **Active** (public branch, buildid 23773332+). systemd unit `cs2.service` (user `steam`), install at `/home/steam/cs2`. Direct game port **27015 UDP**; clients reach it over **Steam Datagram Relay** (server has `sv_setsteamaccount`/GSLT), not a direct IP. server.cfg at `game/csgo/cfg/server.cfg`; passwords in gitignored `cs2-pass`.
- **Updating**: `systemctl stop cs2` → `sudo -u steam /home/steam/steamcmd/steamcmd.sh +force_install_dir /home/steam/cs2 +login anonymous +app_update 730 +quit` → `systemctl start cs2`. A client/server **build mismatch** shows as `[Prediction] Expected tick base...` console spam + laggy/rubberbandy feel; fix = update server to latest public AND set the **client** to public branch (Steam → CS2 → Betas → None).
- **RCON**: in-game `rcon` command is **broken** in CS2 for this setup (Steam relay) — use the external tool **`cs2-rcon.py`** (repo root; reads `rcon_password` from `cs2-pass`). Server-side RCON had to be bound to all interfaces: ExecStart has **`-ip 0.0.0.0`** (was binding to loopback `127.0.1.1` from `/etc/hosts`, so RCON was unreachable from the LAN).
- **In-game admin** = Metamod:Source + CounterStrikeSharp + **CS2-SimpleAdmin** (SQLite, no DB server). Plugins in `game/csgo/addons/counterstrikesharp/`; Metamod registered via `Game csgo/addons/metamod` in `gameinfo.gi`. Dependency chain: SimpleAdmin → MenuManagerCS2 + PlayerSettings → AnyBaseLib (all NickFox007). Admins are **allowlist-only** in `addons/counterstrikesharp/configs/admins.json` (currently you + DeZalino, `@css/root`); everyone else has no flags. Admin commands (`!admin`, `!map`, `css_cvar bot_quota N`) are **client commands** — only work typed by a player in-game, never from RCON/server console. **CS2 updates can break Metamod/CSS** — if the server won't boot after a big patch, update Metamod/CSS or pull the metamod line from `gameinfo.gi`. Command reference: [`cs2-admin-commands.csv`](./cs2-admin-commands.csv) (full) and [`cs2-admin-commands-console.csv`](./cs2-admin-commands-console.csv) (console + examples).
- **Game mode**: set by cvars `game_type` + `game_mode` *together* (game_mode's meaning depends on game_type), applied only on a **map reload**. Combos: Casual 0/0, Competitive 0/1, Wingman 0/2, ArmsRace 1/0, Demolition 1/1, **Deathmatch 1/2**. Boot default is **Deathmatch on de_dust2** (set in the unit's `+game_type 1 +game_mode 2 +map de_dust2`). **Presets**: `game/csgo/cfg/mode_*.cfg` (dm/comp/casual/wingman/armsrace/demolition/**scoutz**) each set the cvars + a `changelevel` (de_dust2, except **wingman → de_sanctum**, **scoutz → ar_shoots**); wired into SimpleAdmin's `CustomServerCommands` so they appear in **`!admin` → Custom Commands** (one click switches mode; or `css_rcon exec mode_dm`). Every normal preset first does `exec scoutz_cleanup` (see ScoutzNKnives below). SimpleAdmin's `CS2-SimpleAdmin.json` is **JSONC** (leading `//` header) — strip the comment line before parsing with a JSON tool.
- **Demo recording**: **cs2-demo-recorder** plugin (Kandru, CSSharp, .NET 10) at `addons/counterstrikesharp/plugins/DemoRecorder/`. Config `addons/counterstrikesharp/configs/plugins/DemoRecorder/DemoRecorder.json`: records to `game/csgo/demos/`, `minimum_players_for_recording: 2`, `disable_recording_during_warmup: true`. Uses SourceTV/GOTV under the hood (auto-enables `tv_enable` only while recording; idle shows `tv_enable false` — normal). **rootfs is 100GB** (grown from 80GB via `pct resize 117 rootfs +20G`; ~27GB free, game install is ~55GB) so a **root cron** `/home/steam/cs2/demo-cleanup.sh` (daily 05:00) deletes demos >7 days old and trims the folder to <3GB (oldest-first). Keep several GB free for CS2 patch downloads; raise `CAP_MB` in the script if more demo history is wanted. Plugin config is read at load — apply changes with `systemctl restart cs2` (`css_plugins reload DemoRecorder` fails; the reload command wants the module name, not the folder).
- **ScoutzNKnives mode** (SSG08 + knife, high-gravity + bhop, round-based on **ar_shoots**): plugin `asapverneri/CS2-ScoutzKnivez` (v1.6). It's **global-while-loaded** (strips weapons + forces movement/economy cvars on every spawn/round, on any map) and CSSharp **auto-loads everything in `plugins/` at boot** — so to keep it OFF by default the DLL lives **outside** the auto-load dir at `addons/counterstrikesharp/plugins-disabled/scoutzknivez/scoutzknivez.dll`. `mode_scoutz.cfg` loads it **by absolute path** (`css_plugins load <abspath>.dll` accepts absolute/relative paths) then `changelevel ar_shoots`. `scoutz_cleanup.cfg` unloads it **by that same path** (unload-by-name is unreliable) and resets the forced cvars to defaults (gravity 800, maxvelocity 3500, stamina, bunnyhop off, economy); it's `exec`'d at the top of every normal `mode_*.cfg`. Config `configs/plugins/scoutzknivez/scoutzknivez.json` (VIP perks disabled to keep it pure scout+knife). Caveats: **do NOT put `css_plugins unload` in `server.cfg`** — server.cfg re-execs on *every* map load (order: server_default.cfg → server.cfg → gamemode_*.cfg) and would unload it right after mode_scoutz loads it; per-map `<mapname>.cfg` is **not** auto-exec'd in CS2. Repeated in-session toggles leave harmless stale `[#n:UNLOADED]` slots in `css_plugins list` (clear on restart). The plugin only applies its cvars/loadout during live rounds, so full behavior can only be confirmed with a real player connected (not while empty/hibernating).
- **Warcraft (WC3) mode — researched, NOT installed** (pending decision): the popular **War3CS2** (war3cs2.wiki.gg) is **closed-source** (Steam Workshop client pack only, no server download) — not self-hostable. The installable open-source option is **`NightFuryPrime/CS2-Warcraft-Plugin`** (aka WarcraftPlugin, maintained fork of Wngui's; v4.1.1 May 2026): CSSharp drop-in, **SQLite `database.db`** (no DB server, like SimpleAdmin), Linux OK, targets `net8.0`/CSS.API `1.0.368` (roll-forward onto our .NET 10 — boot-test to confirm), self-contained menu (no extra MenuManager). 14 races, XP/levels **global-while-loaded** (a "Warcraft server" mode, not a per-map toggle; run on its own rotation). Small maintainer + deep engine use = higher CS2-patch fragility than the admin stack.

## Host memory / ZFS ARC
- Host: **31 GiB RAM**, Intel i9-10900X (20 threads). ZFS pool `data` (928 GB) backs the Samba share, backups, and the ISO/snapshot dir-storages; the host root is LVM-thin (`local-lvm`), not ZFS.
- **ZFS ARC is capped at 8 GB.** Set in `/etc/modprobe.d/zfs.conf` (`options zfs zfs_arc_max=8589934592`); applied live with `echo 8589934592 > /sys/module/zfs/parameters/zfs_arc_max` (no reboot); `update-initramfs -u -k all` makes it persist at boot. ARC trims to a lowered `c_max` almost immediately. To change: edit that file, re-echo, re-run initramfs.
- **Why (incident, 2026-07-19)**: after standing up the Palworld server (the **3rd** game server), a memory review found ARC had grown to the stock ~50%-of-RAM default (**~15.3 GB**) — the single largest consumer on the box, larger than any VM — leaving the 31 GB host looking ~84% "used" and **swapping (2.3 GB)**. ARC counts as "used" in `free`, so it masked how tight things were. Capping to 8 GB freed **~7 GB** (used 26→19 GiB, available 4.5→11 GiB); `swapoff -a && swapon -a` then reclaimed swap to 0. ARC is reclaimable cache, so the smaller cap only mildly affects file-server/backup throughput.
- **Capacity note**: the three game servers can demand up to ~24 GB together — Windrose VM (8 GB **hard-locked** while running), CS2 (up to 8 GB), Palworld (up to 8 GB) — on a 31 GB host. The ARC cap is the interim mitigation; a physical **RAM upgrade** is the real fix (on hold). Watch `free -h` / swap if all three fill up simultaneously.

## Key Patterns
- All containers on **vmbr0** bridge
- Docker-in-LXC needs: privileged, `nesting=1,keyctl=1` features, AppArmor removed
- Reverse proxy (LXC 114): per-site files in `/etc/nginx/sites-available/`
- DNS entries (Pi-hole): `"IP hostname"` in `hosts` array in `/etc/pihole/pihole.toml`
- **Secrets stay local** — server passwords, RCON passwords, SMB creds, etc. live in gitignored files (`*-pass`, `smb-pass`, ...), never in tracked docs
- Backups: explicit VMID list in vzdump job (`/etc/pve/jobs.cfg`)
  - **New containers must be added manually** to the `vmid` line
  - **Exclude containers with rootfs > 40GB** (game servers, large installs) — they're re-downloadable and waste backup storage
  - Currently excluded: LXC 117 (cs2, 80GB), VM 119 (windrose, 120GB Windows). World saves live in `C:\Game_Servers\Windrose_Server\R5\Saved` — back those up separately if they matter, not the whole VM.

## Adding a New Service

1. **Create LXC container**
   ```bash
   ssh root@192.168.68.200 pct create <VMID> <TEMPLATE> \
       --hostname <name> --storage local-lvm --rootfs local-lvm:<size>G \
       --cores <n> --memory <mb> --swap 1024 \
       --net0 "name=eth0,bridge=vmbr0,ip=dhcp,type=veth" \
       --onboot 1 --unprivileged 0 --features "nesting=1,keyctl=1"
   ```

2. **Reserve DHCP IP** on the Deco app
   - Boot the container/VM first and let it pull a DHCP lease so the Deco **detects it** in the connected-clients list
   - In the Deco app, **reserve from that detected list** — do NOT manually type the MAC address
   - (MAC, if needed for reference: `grep hwaddr /etc/pve/lxc/<VMID>.conf`)

3. **Add DNS** (Pi-hole, LXC 110)
   - Edit `/etc/pihole/pihole.toml` — add `"<IP> <name>.home"` to `hosts` array
   - DNS points to **proxy IP** (192.168.68.53), not the container directly
   - Reload: `/usr/local/bin/pihole reloaddns`

4. **Add reverse proxy** (Nginx, LXC 114)
   - Create `/etc/nginx/sites-available/<name>` with server block
   - Symlink to `sites-enabled`, then `nginx -t && systemctl reload nginx`

5. **Add to backups** (if rootfs ≤ 40GB)
   - Add VMID to the `vmid` line in `/etc/pve/jobs.cfg`
   - Skip for large containers (game servers, etc.) — they can be re-downloaded

6. **If Docker-in-LXC**: remove AppArmor inside container (`apt-get remove apparmor`)
