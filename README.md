# Proxmox Homelab

## Network Overview

```
                        ┌─────────────────────────────────┐
                        │         INTERNET                │
                        └────────────┬────────────────────┘
                                     │
                        ┌────────────▼────────────────────┐
                        │   Deco Router (192.168.68.1)    │
                        │   DHCP Server / Gateway         │
                        │   Subnet: 192.168.68.0/24       │
                        └────────────┬────────────────────┘
                                     │ Gigabit Ethernet
                        ┌────────────▼────────────────────┐
                        │   Proxmox Host (192.168.68.200) │
                        │   NIC: enp0s31f6                │
                        │   Bridge: vmbr0                 │
                        └──┬──────────┬──────────┬────────┘
                           │          │          │
               ┌───────────▼──┐  ┌────▼──────┐  ┌▼───────────┐
               │   Pi-hole    │  │   Samba   │  │   Gotify   │
               │ LXC 110      │  │ LXC 111   │  │ LXC 112    │
               │ .68.51       │  │ .68.58    │  │ .68.59     │
               │ DNS/Ad-block │  │ File Svr  │  │ Push Notif │
               └──────────────┘  └───────────┘  └────────────┘

         Stopped VMs (old subnet — need IP updates):
         ┌──────────┐  ┌──────────┐  ┌──────────┐
         │  ipa1    │  │  ipa2    │  │ ansible  │
         │  VM 101  │  │  VM 102  │  │  VM 103  │
         │ FreeIPA  │  │ FreeIPA  │  │ Ansible  │
         └──────────┘  └──────────┘  └──────────┘
```

## Storage Architecture

```
  ┌─────────────────────────────────────────────────┐
  │              NVMe (Samsung 980 500GB)            │
  │                                                  │
  │  ┌──────────────┐ ┌──────┐ ┌──────────────────┐ │
  │  │ pve/root 96G │ │swap  │ │ pve/data 338G    │ │
  │  │   ext4 → /   │ │ 8G   │ │ LVM thin pool    │ │
  │  │  Proxmox OS  │ │      │ │                  │ │
  │  └──────────────┘ └──────┘ │ LXC 110 rootfs   │ │
  │                            │ LXC 111 rootfs   │ │
  │                            │ LXC 112 rootfs   │ │
  │                            └──────────────────┘ │
  └─────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────┐
  │     HDDs — ZFS Mirror (2x Seagate 1TB)          │
  │         Pool: "data"  ~928G usable              │
  │                                                  │
  │  ┌──────────────────────────────────────┐       │
  │  │ data/samba/                           │       │
  │  │   ├── public     (quota: 50G)        │       │
  │  │   ├── scott      (quota: 100G)       │       │
  │  │   └── katherine  (quota: 100G)       │       │
  │  └──────────────────────────────────────┘       │
  │  ┌──────────────────────────────────────┐       │
  │  │ /data/iso-images/  (ISOs + VM disks) │       │
  │  │   VM 101, 102, 103 qcow2 images     │       │
  │  └──────────────────────────────────────┘       │
  │  ┌──────────────────────────────────────┐       │
  │  │ /data/snapshots/   (vzdump backups)  │       │
  │  └──────────────────────────────────────┘       │
  └─────────────────────────────────────────────────┘
```

## Services

### Pi-hole — DNS & Ad Blocking (LXC 110)

**What it does**: Pi-hole acts as the DNS server for the network. It resolves local
hostnames (like `samba.home`, `gotify.home`) and blocks ad/tracking domains for all
devices on the network.

**How it works**:
```
Device makes DNS query (e.g., "gotify.home")
    │
    ▼
Pi-hole (192.168.68.51:53)
    │
    ├── Local record found? → Return IP (e.g., 192.168.68.59)
    ├── On blocklist?       → Return 0.0.0.0 (blocked)
    └── Neither?            → Forward to upstream DNS (Google/Cloudflare)
```

**Local DNS Records** (configured in `/etc/pihole/pihole.toml`):
| Hostname | IP |
|---|---|
| proxmox.home | 192.168.68.200 |
| pihole.home | 192.168.68.51 |
| samba.home | 192.168.68.58 |
| gotify.home | 192.168.68.59 |
| cs2.home | 192.168.68.60 |

**Key Commands**:
```bash
# Access the container
pct exec 110 -- bash

# Reload DNS after config changes
pct exec 110 -- /usr/local/bin/pihole reloaddns

# Add a new local DNS entry (edit pihole.toml, dns.hosts array)
# Then reload DNS

# Check pihole status
pct exec 110 -- /usr/local/bin/pihole status

# Update gravity (ad blocklists)
pct exec 110 -- /usr/local/bin/pihole -g

# Web UI
http://pihole.home/admin
```

**Config file**: `/etc/pihole/pihole.toml` (Pi-hole v6 format)

---

### Samba — File Server (LXC 111)

**What it does**: Provides Windows-compatible (SMB) file shares for Scott and Katherine.
Each user has a private folder plus a shared public folder. Data lives on the ZFS mirror
for redundancy.

**How it works**:
```
Windows/Mac/Linux client
    │
    ▼ SMB protocol (port 445)
Samba (192.168.68.58)
    │
    ├── Authenticate user (scott/katherine)
    │
    ├── \\samba.home\public     → /mnt/shares/public    (ZFS, 50G quota)
    ├── \\samba.home\scott      → /mnt/shares/scott     (ZFS, 100G quota)
    └── \\samba.home\katherine  → /mnt/shares/katherine (ZFS, 100G quota)
    │
    ▼ bind mounts
ZFS datasets on redundant mirror (data/samba/*)
```

**Share Permissions**:
| Share | Who Can Access | Permissions |
|---|---|---|
| `public` | scott, katherine | Both read/write, shared group ownership |
| `scott` | scott only | Private, 700 |
| `katherine` | katherine only | Private, 700 |

**Connecting from a Client**:
```
Windows:    \\192.168.68.58\scott  (or \\samba.home\scott if using Pi-hole DNS)
Mac:        smb://samba.home/scott  (Finder → Go → Connect to Server)
Linux:      smb://samba.home/scott
```

**Key Commands**:
```bash
# Access the container
pct exec 111 -- bash

# Change a user's Samba password
pct exec 111 -- smbpasswd scott
pct exec 111 -- smbpasswd katherine

# Add a new Samba user
pct exec 111 -- useradd -M -s /usr/sbin/nologin newuser
pct exec 111 -- usermod -aG samba-users newuser
pct exec 111 -- smbpasswd -a newuser

# Check Samba config syntax
pct exec 111 -- testparm -s

# Restart Samba
pct exec 111 -- systemctl restart smbd nmbd

# Check connected clients
pct exec 111 -- smbstatus

# Check ZFS quota usage
zfs list -o name,used,avail,quota -r data/samba
```

**Config file**: `/etc/samba/smb.conf`

**Storage flow**:
```
LXC 111 container
  /mnt/shares/public     ← bind mount ← ZFS dataset data/samba/public    (quota=50G)
  /mnt/shares/scott      ← bind mount ← ZFS dataset data/samba/scott     (quota=100G)
  /mnt/shares/katherine  ← bind mount ← ZFS dataset data/samba/katherine (quota=100G)
```

---

### Gotify — Push Notifications (LXC 112)

**What it does**: Receives notifications from Proxmox (backup results, system alerts)
and pushes them to your phone via the Gotify app.

**How it works**:
```
Proxmox event (e.g., backup completes)
    │
    ▼
PVE notification system
    │
    ├── Matcher: "gotify-all" (mode: all)
    │       routes to endpoint "gotify-push"
    │
    ▼
Gotify server (192.168.68.59:80)
    │
    ▼ WebSocket push
Gotify app on phone → buzz/notification
```

**Key Commands**:
```bash
# Access the container
pct exec 112 -- bash

# Check Gotify service status
pct exec 112 -- systemctl status gotify

# Restart Gotify
pct exec 112 -- systemctl restart gotify

# Send a test notification from Proxmox host
curl -s 'http://192.168.68.59:80/message?token=<APP_TOKEN>' \
  -F 'title=Test' -F 'message=Hello' -F 'priority=5'

# Web UI (manage apps, view messages, change password)
http://gotify.home
```

**Proxmox notification config**: `/etc/pve/notifications.cfg`
- Endpoint: `gotify-push` → `http://192.168.68.59:80`
- Matcher: `gotify-all` → routes all events to gotify-push

**Binary location**: `/opt/gotify/gotify-linux-amd64`
**Systemd service**: `gotify.service`

---

### CS2 — Dedicated Game Server (LXC 117)

**What it does**: Runs a Counter-Strike 2 dedicated server on the AnimGraph2 beta branch
for testing the new animation system with bots and friends.

**How it works**:
```
Friend connects via CS2 console
    │
    ▼ connect <public-ip>:27015 (password: theranchero)
Port forwarding on Deco router
    │
    ▼ UDP/TCP 27015 → 192.168.68.60:27015
CS2 Dedicated Server (LXC 117)
    │
    ├── AnimGraph2 beta branch (via SteamCMD)
    ├── Casual mode, de_dust2, 10 bots
    └── sv_cheats enabled for testing
```

**Connection Info**:
| Setting | Value |
|---|---|
| Server IP | `<public-ip>:27015` |
| Server Password | `theranchero` |
| RCON Password | `thehalford` |
| Game Mode | Casual (game_type 0, game_mode 0) |
| Beta Branch | `animgraph_2_beta` |

**Key Commands**:
```bash
# Access the container
pct exec 117 -- bash

# Start/stop/restart CS2
pct exec 117 -- systemctl start cs2
pct exec 117 -- systemctl stop cs2
pct exec 117 -- systemctl restart cs2

# Check server status
pct exec 117 -- systemctl status cs2

# View server logs
pct exec 117 -- journalctl -u cs2 -f

# Update CS2 (stop server first)
pct exec 117 -- systemctl stop cs2
pct exec 117 -- su - steam -c '~/steamcmd/steamcmd.sh +force_install_dir ~/cs2 +login anonymous +app_update 730 -beta animgraph_2_beta validate +quit'
pct exec 117 -- systemctl start cs2
```

**Config files**:
- Server config: `/home/steam/cs2/game/csgo/cfg/server.cfg`
- Systemd service: `/etc/systemd/system/cs2.service`

**Port forwarding** (configured on Deco router):
| Port | Protocol | Purpose |
|---|---|---|
| 27015 | TCP+UDP | Game server |
| 27020 | UDP | RCON |
| 27005 | UDP | Steam client |

---

### Proxmox Backups

**What it does**: Automatically backs up all VMs and containers weekly to the ZFS mirror,
with 4-week rolling retention. Notifications go to Gotify.

**How it works**:
```
Sunday 2:00 AM
    │
    ▼
vzdump (Proxmox backup tool)
    │
    ├── Snapshot each VM/CT (no downtime)
    ├── Compress with zstd
    ├── Write to /data/snapshots/dump/
    │
    ▼
Prune old backups (keep last 4 weekly)
    │
    ▼
Send notification → Gotify → phone
```

**What gets backed up**: ALL VMs and containers (the `all 1` flag)
- VM 101 (ipa1), VM 102 (ipa2), VM 103 (ansible)
- LXC 110 (pihole), LXC 111 (samba), LXC 112 (gotify)
- Any new VM/container created in the future

**Backup storage**: `/data/snapshots/dump/` on ZFS mirror (redundant)

**Key Commands**:
```bash
# List existing backups
ls -lh /data/snapshots/dump/

# Manually trigger a backup of a specific VM/CT
vzdump <VMID> --storage snapshots --compress zstd --mode snapshot

# Restore a backup
qmrestore /data/snapshots/dump/<backup-file> <NEW_VMID>
# or for containers:
pct restore <NEW_VMID> /data/snapshots/dump/<backup-file> --storage local-lvm

# View backup job config
cat /etc/pve/jobs.cfg

# Check backup schedule in the web UI:
# Datacenter → Backup (in the left panel)
```

**Backup job config**: `/etc/pve/jobs.cfg`

---

## Maintenance

### ZFS Health
```bash
# Check pool status (errors, scrub history)
zpool status data

# Manual scrub (automated monthly via systemd timer)
zpool scrub data

# Check dataset usage and quotas
zfs list -o name,used,avail,quota -r data

# Check scrub timer
systemctl status zfs-scrub-monthly@data.timer
```

### SMART Disk Health
```bash
# Check disk health
smartctl -H /dev/sda
smartctl -H /dev/sdb
smartctl -a /dev/nvme0n1    # NVMe

# Full SMART attributes
smartctl -A /dev/sda
```

### System Temperatures
```bash
sensors    # requires lm-sensors (installed)
```

### Proxmox Updates
```bash
apt update && apt dist-upgrade
# Using pve-no-subscription repo (enterprise repo disabled)
# /etc/apt/sources.list.d/pve-enterprise.list — commented out
```

---

## Quick Access Reference

| Service | URL / Address | Port |
|---|---|---|
| Proxmox Web UI | https://proxmox.home:8006 | 8006 |
| Pi-hole Admin | http://pihole.home/admin | 80 |
| Gotify Web UI | http://gotify.home | 80 |
| Samba Shares | \\\\samba.home\\<share> | 445 |
| CS2 Server | connect cs2.home:27015 | 27015 |

| Task | Command |
|---|---|
| SSH to Proxmox | `ssh root@proxmox` |
| Shell into a container | `pct exec <VMID> -- bash` |
| Start/stop a VM | `qm start <VMID>` / `qm stop <VMID>` |
| Start/stop a container | `pct start <VMID>` / `pct stop <VMID>` |
| List all VMs | `qm list` |
| List all containers | `pct list` |
| Check ZFS pool | `zpool status data` |
| Check LVM thin pool | `lvs pve` |
| View backup jobs | `cat /etc/pve/jobs.cfg` |
| Reload Pi-hole DNS | `pct exec 110 -- /usr/local/bin/pihole reloaddns` |

---

## Diagrams To-Do

Future diagrams to create in a diagramming tool (draw.io, Excalidraw, etc.):

- [ ] Full network topology with IPs, VLANs (once segmentation is planned)
- [ ] Storage flow: physical disks → LVM/ZFS → PVE storage → VMs/CTs
- [ ] Backup lifecycle: schedule → snapshot → compress → store → prune → notify
- [ ] Service dependency map: what breaks if each service goes down
- [ ] Future state: IPA identity flow → Ansible config push → auto-enrollment
