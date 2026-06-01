# Accessing Proxmox Containers & VMs

## SSH to Proxmox Host

```bash
ssh root@proxmox
# or
ssh root@192.168.68.200
```

Note: Requires ssh-agent running with key loaded. On Windows (admin PowerShell):
```powershell
Start-Service ssh-agent
ssh-add ~\.ssh\id_ed25519
```

## Accessing LXC Containers (from Proxmox host)

Containers don't have SSH keys set up, so you reach them through the host:

```bash
# Get a shell inside a container
pct exec <VMID> -- bash

# Run a single command
pct exec <VMID> -- <command>

# Examples
pct exec 110 -- bash              # shell into pihole
pct exec 111 -- bash              # shell into samba
pct exec 111 -- smbpasswd scott   # change scott's samba password
```

## Accessing VMs (from Proxmox host)

```bash
# Open the console (if serial is configured)
qm terminal <VMID>

# Send commands via guest agent (if installed)
qm guest exec <VMID> -- <command>

# Otherwise use the web console at https://192.168.68.200:8006
```

## Quick Reference

| VMID | Name      | Type | IP              | DNS            | Access                  |
|------|-----------|------|-----------------|----------------|-------------------------|
| 110  | pihole    | LXC  | 192.168.68.51   | pihole.home    | `pct exec 110 -- bash`  |
| 111  | samba     | LXC  | 192.168.68.58   | samba.home     | `pct exec 111 -- bash`  |
| 112  | gotify    | LXC  | 192.168.68.59   | gotify.home    | `pct exec 112 -- bash`  |
| 113  | bookstack | LXC  | 192.168.68.52   | wiki.home      | `pct exec 113 -- bash`  |
| 101  | ipa1      | VM   | unknown/stopped | —              | web console or SSH      |
| 102  | ipa2      | VM   | unknown/stopped | —              | web console or SSH      |
| 103  | ansible   | VM   | unknown/stopped | —              | web console or SSH      |
