# Proxmox Homelab

## Access
- Proxmox host: `ssh root@192.168.68.200`
- Web UI: https://192.168.68.200:8006

## Network
- Subnet: 192.168.68.0/22 (NOT /24 — Deco router uses /22)
- Gateway: 192.168.68.1 (TP-Link Deco mesh)
- DNS: Pi-hole at 192.168.68.51 (LXC 110)
- **CRITICAL**: LXC containers MUST use `ip=dhcp` — static IPs break networking (Deco has ARP protection/IP-MAC binding that drops traffic from IPs it didn't assign). Reserve IPs on the Deco router admin page instead.

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
| 117 | cs2 | .60 | CS2 Dedicated Server (AnimGraph2 Beta) |

## Key Patterns
- All containers on **vmbr0** bridge
- Docker-in-LXC needs: privileged, `nesting=1,keyctl=1` features, AppArmor removed
- Reverse proxy (LXC 114): per-site files in `/etc/nginx/sites-available/`
- DNS entries (Pi-hole): `"IP hostname"` in `hosts` array in `/etc/pihole/pihole.toml`
- Backups: explicit VMID list in vzdump job (`/etc/pve/jobs.cfg`)
  - **New containers must be added manually** to the `vmid` line
  - **Exclude containers with rootfs > 40GB** (game servers, large installs) — they're re-downloadable and waste backup storage
  - Currently excluded: LXC 117 (cs2, 80GB)

## Adding a New Service

1. **Create LXC container**
   ```bash
   ssh root@192.168.68.200 pct create <VMID> <TEMPLATE> \
       --hostname <name> --storage local-lvm --rootfs local-lvm:<size>G \
       --cores <n> --memory <mb> --swap 1024 \
       --net0 "name=eth0,bridge=vmbr0,ip=dhcp,type=veth" \
       --onboot 1 --unprivileged 0 --features "nesting=1,keyctl=1"
   ```

2. **Reserve DHCP IP** on Deco router for the container's MAC
   - Get MAC: `grep hwaddr /etc/pve/lxc/<VMID>.conf`

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
