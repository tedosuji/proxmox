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
| 117 | cs2 | .60 | CS2 Dedicated Server (AnimGraph2 Beta) — **inactive** (service stopped + disabled) |
| 118 | inventree | .64 | Parts Inventory (leverless controller business) |
| 119 | windrose | .67 | Windrose Dedicated Server (**Windows 11 VM**, not LXC) |

## Windows VM (119, Windrose game server)
- **QEMU/KVM VM, not an LXC.** Win 11 Home. Manage over **SSH** (`ssh potat@192.168.68.67`, PowerShell) or Proxmox noVNC console. No RDP (Home can't host it).
- **CPU must be a named model, NOT `host`** — `cpu: host` BSODs Win 11 24H2/25H2 setup (`PAGE_FAULT_IN_NONPAGED_AREA`, fbwf.sys). Using `x86-64-v3` (host is Intel i9-10900X, has AVX2).
- **q35 + OVMF + TPM 2.0 + Secure Boot** (Win 11 requirement). Disk on `local-lvm` (SSD), VirtIO SCSI.
- **Install gotchas**: use E1000 NIC during install/OOBE (Win has no built-in VirtIO NIC driver → no internet for the MS-account step), then install virtio-win guest tools and swap NIC to VirtIO. Load `vioscsi\w11\amd64` driver at the disk-select screen.
- **Windrose server**: SteamCMD app `4129620`, `login anonymous` (no account needed). Installed to `C:\Game_Servers\Windrose_Server`. First SteamCMD run only self-updates (exit 7) — **run it twice**. UE5 needs the bundled **VC++ redist** (`Engine\Extras\Redist\en-us\vc_redist.x64.exe`) or the exe dies with `0xC0000135` and no log.
- Config: `R5\ServerDescription.json` (edit only while stopped). Direct-connect on **7777 TCP+UDP**, password-protected, 6 players. Server name/password/invite-code kept in gitignored `windrose-*` files.
- Auto-start: Scheduled Task `WindroseServer` (SYSTEM, at boot). Nightly save backup task `WindroseSaveBackup` → `//192.168.68.58/scott/windrose-backups`. SSH firewall scoped to `192.168.68.0/22`; only 7777 open inbound.
- **Player dashboard** at `windrose.home` (LAN-only): live crew + server settings. Parser `C:\ProgramData\windrose-web\parse-players.ps1` on the VM reads `R5.log` + the JSON configs → JSON; webapps LXC 115 pulls it every 60s via a **restricted forced-command SSH key** (`/root/.ssh/windrose_pull`, locked to only run the parser) → `/var/www/windrose`, fronted by proxy 114 + Pi-hole `windrose.home`→.53.

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
