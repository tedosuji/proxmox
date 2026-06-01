# Gotify — The Idiot's Guide

## What Is Gotify?

Gotify is a self-hosted push notification server. Think of it like your own private
notification service — instead of relying on email or SMS, any application (Proxmox,
scripts, cron jobs, whatever) can send a message to Gotify, and Gotify pushes it to
your phone in real-time.

It's a single Go binary. No database server needed (it uses SQLite internally). No
cloud dependency. It runs entirely on your network.

## Core Concepts

Gotify has three key concepts. Understanding these is the whole game:

```
┌─────────────────────────────────────────────────────────────────┐
│                        GOTIFY SERVER                            │
│                    (http://gotify.home)                         │
│                                                                 │
│   ┌──────────────────┐          ┌──────────────────┐           │
│   │   APPLICATIONS   │          │     CLIENTS      │           │
│   │                  │          │                  │           │
│   │  Things that     │          │  Things that     │           │
│   │  SEND messages   │          │  RECEIVE messages│           │
│   │                  │          │                  │           │
│   │  Each app gets   │          │  Each client gets│           │
│   │  an APP TOKEN    │          │  a CLIENT TOKEN  │           │
│   │                  │          │                  │           │
│   │  Examples:       │          │  Examples:       │           │
│   │  - Proxmox       │          │  - Your phone    │           │
│   │  - A cron script │          │  - Web browser   │           │
│   │  - Ansible       │          │                  │           │
│   └────────┬─────────┘          └────────▲─────────┘           │
│            │                             │                     │
│            │    ┌──────────────────┐      │                     │
│            └───►│    MESSAGES      │──────┘                     │
│                 │                  │                            │
│                 │  title, body,    │                            │
│                 │  priority (1-10) │                            │
│                 └──────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

### 1. Applications (senders)

An Application is anything that SENDS notifications. When you create an application
in Gotify, it gets a unique **App Token**. That token is what the sender uses to
authenticate when pushing a message.

**You give App Tokens to things that need to SEND you messages.**

In our setup, there is one application:
- **Proxmox** — sends backup results, system alerts

You could add more later:
- A script that monitors disk health
- Ansible reporting deployment results
- A cron job that checks if a service is down

### 2. Clients (receivers)

A Client is anything that RECEIVES notifications. When you log into Gotify from
your phone app or browser, that session becomes a client. Clients get a **Client Token**
used to open a WebSocket connection for real-time push.

**You don't usually manage Client Tokens manually** — the phone app handles this when
you log in.

### 3. Messages

A Message is the actual notification. It has:
- **title** — the subject line (e.g., "Backup Complete")
- **message** — the body text (e.g., "VM 111 backed up successfully")
- **priority** — a number from 1-10 that controls how the phone app alerts you

**Priority levels** (these are conventions, not strict rules):
| Priority | Meaning | Phone behavior |
|----------|---------|----------------|
| 1-3 | Low / info | Silent, just shows in app |
| 4-7 | Normal | Standard notification buzz |
| 8-10 | High / urgent | Persistent alert, loud |

## How Messages Flow

```
1. Something happens (e.g., Proxmox finishes a backup)

2. Proxmox POSTs a message to Gotify using the App Token:

   POST http://gotify.home/message?token=<APP_TOKEN>
   title=Backup Complete
   message=All VMs backed up successfully
   priority=5

3. Gotify receives the message, stores it in its SQLite database

4. Gotify checks: are any clients connected via WebSocket?

5. Your phone has the Gotify app running in the background,
   maintaining a WebSocket connection to the server

6. Gotify pushes the message over the WebSocket → phone buzzes
```

The key insight: **the phone app doesn't poll**. It holds a persistent WebSocket
connection open. That's why the app needs to run in the background and not be
battery-optimized — if Android kills it, the WebSocket closes and you stop getting
notifications until you re-open the app.

## How Proxmox Integration Works

Proxmox 8.x has native Gotify support in its notification system. The config lives
in two files on the Proxmox host:

**`/etc/pve/notifications.cfg`** — defines endpoints and matchers:
```
gotify: gotify-push                          ← endpoint name
    comment Gotify push notifications
    server http://192.168.68.59:80           ← where to send

matcher: gotify-all                          ← matcher name
    comment Route all notifications to Gotify
    mode all                                 ← match ALL events
    target gotify-push                       ← send to this endpoint
```

**`/etc/pve/priv/notifications.cfg`** — stores the App Token (secret):
```
gotify: gotify-push
    token <APP_TOKEN>                   ← the Gotify App Token
```

**How the pieces connect**:
```
Proxmox event occurs
    │
    ▼
Notification system checks all matchers
    │
    ├── "default-matcher" (mode: all) → target: mail-to-root → (email, broken)
    │
    └── "gotify-all" (mode: all) → target: gotify-push
            │
            ▼
        Look up endpoint "gotify-push"
            │
            ├── server: http://192.168.68.59:80
            ├── token: <APP_TOKEN> (from priv config)
            │
            ▼
        HTTP POST → Gotify server → WebSocket → phone
```

You can also filter matchers by severity or event type instead of `mode all`.
For example, you could create a matcher that only fires on errors.

## Your Current Setup

### Container (LXC 112)
```
Hostname:   gotify
IP:         192.168.68.59
RAM:        128 MB
Disk:       1 GB (rootfs on NVMe LVM thin)
OS:         Debian 13
Autostart:  yes (onboot: 1)
```

### Gotify Server
```
Binary:     /opt/gotify/gotify-linux-amd64
Data dir:   /opt/gotify/data/ (SQLite DB, images, plugins)
Config:     None (using defaults — port 80, no TLS)
Service:    gotify.service (systemd, auto-restart)
Web UI:     http://gotify.home
```

### Default Configuration

Gotify uses defaults when no `config.yml` exists:
- **Port**: 80
- **Database**: SQLite at `data/gotify.db`
- **No TLS** (plain HTTP — fine for LAN, don't expose to internet)
- **Default admin**: `admin` (you already changed the password)

If you ever want to customize, create `/opt/gotify/config.yml`:
```yaml
server:
  port: 80           # change the port
  ssl:
    enabled: false    # enable TLS if exposing externally
    redirecttohttps: false
    letsencrypt:
      enabled: false
database:
  dialect: sqlite3
  connection: data/gotify.db
defaultuser:
  name: admin
  pass: admin         # only used on first run
```

## Common Tasks

### Send a test notification (from Proxmox host)
```bash
curl -s 'http://192.168.68.59:80/message?token=YOUR_APP_TOKEN' \
  -F 'title=Test Alert' \
  -F 'message=This is a test' \
  -F 'priority=5'
```

### Send a notification from a bash script
```bash
#!/bin/bash
GOTIFY_URL="http://gotify.home/message"
GOTIFY_TOKEN="YOUR_APP_TOKEN"

notify() {
  curl -s "$GOTIFY_URL?token=$GOTIFY_TOKEN" \
    -F "title=$1" \
    -F "message=$2" \
    -F "priority=${3:-5}"
}

# Usage:
notify "Disk Warning" "ZFS pool is 90% full" 8
notify "Backup Done" "Weekly backup completed" 4
```

### Create a new Application (via web UI)
1. Go to http://gotify.home
2. Log in
3. Click "Apps" in the sidebar
4. Click "Create Application"
5. Name it (e.g., "Disk Monitor")
6. Copy the generated App Token
7. Use that token in your script/service

### Create a new Application (via API)
```bash
curl -s -u admin:YOURPASSWORD \
  http://gotify.home/application \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{"name":"My Script","description":"Sends alerts from cron"}'
```

### Delete old messages (via API)
```bash
# Delete all messages for an application (app ID 1)
curl -s -u admin:YOURPASSWORD \
  -X DELETE http://gotify.home/application/1/message

# Delete ALL messages
curl -s -u admin:YOURPASSWORD \
  -X DELETE http://gotify.home/message
```

### View messages in terminal (via API)
```bash
curl -s -u admin:YOURPASSWORD http://gotify.home/message | python3 -m json.tool
```

### Add a new Proxmox notification endpoint
If you wanted a second Gotify app (e.g., separate alerts for different priorities):
```bash
# On the Proxmox host:
pvesh create /cluster/notifications/endpoints/gotify \
  --name my-new-endpoint \
  --server http://192.168.68.59:80 \
  --token NEW_APP_TOKEN

pvesh create /cluster/notifications/matchers \
  --name my-new-matcher \
  --mode all \
  --target my-new-endpoint
```

### Check Gotify service health
```bash
# From Proxmox host
pct exec 112 -- systemctl status gotify
pct exec 112 -- journalctl -u gotify --no-pager -n 20

# Check if the API responds
curl -s http://gotify.home/health
# Should return: "green"

# Check server version
curl -s http://gotify.home/version
```

### Restart Gotify
```bash
pct exec 112 -- systemctl restart gotify
```

### Update Gotify
```bash
# Download new binary
pct exec 112 -- curl -sL \
  https://github.com/gotify/server/releases/latest/download/gotify-linux-amd64.zip \
  -o /tmp/gotify.zip

# Stop, replace, start
pct exec 112 -- systemctl stop gotify
pct exec 112 -- unzip -o /tmp/gotify.zip -d /opt/gotify
pct exec 112 -- chmod +x /opt/gotify/gotify-linux-amd64
pct exec 112 -- systemctl start gotify
```

## Phone App Setup

### Android
1. Install from F-Droid or GitHub releases (not on Play Store)
   - F-Droid: search "Gotify"
   - GitHub: https://github.com/gotify/android/releases
2. Open app → enter server URL: `http://192.168.68.59`
3. Log in with your admin credentials
4. Important: **disable battery optimization** for Gotify
   - Settings → Apps → Gotify → Battery → Unrestricted
   - Without this, Android will kill the background WebSocket

### iOS
- No official iOS app exists
- Use the web UI at http://gotify.home (no push, manual refresh)
- Alternative: switch to ntfy in the future (has iOS app)

## Security Notes

- Gotify is running on **plain HTTP** (no TLS). This is fine on your LAN but
  means passwords and tokens are sent in cleartext. Do NOT expose port 80 to the
  internet without adding a reverse proxy with TLS in front of it.
- The **App Token** (`<APP_TOKEN>`) is like a password — anyone with it can
  send you notifications. It's stored in Proxmox's private config file
  (`/etc/pve/priv/notifications.cfg`) which is only readable by root.
- Change the default admin password (you already did this).
- Each Application and Client gets its own token. If one is compromised, you can
  delete just that app/client without affecting others.

## Troubleshooting

| Problem | Check |
|---|---|
| No notifications on phone | Is the app running in background? Battery optimization off? |
| Gotify web UI won't load | `pct exec 112 -- systemctl status gotify` — is it running? |
| Proxmox notifications not arriving | Check token matches: `cat /etc/pve/priv/notifications.cfg` |
| "Unauthorized" API errors | You're using the wrong credentials or token |
| Messages sent but no push | Phone app WebSocket disconnected — reopen the app |
| Container won't start | `pct start 112` and check `journalctl` on the host |

## Architecture Recap

```
┌──────────────────────────────────────────────────────┐
│                  YOUR NETWORK                         │
│                                                       │
│  ┌──────────┐    HTTP POST     ┌──────────────────┐  │
│  │ Proxmox  │ ────────────────►│ Gotify (LXC 112) │  │
│  │ Host     │  App Token auth  │ 192.168.68.59:80 │  │
│  └──────────┘                  │                  │  │
│                                │  SQLite DB       │  │
│  ┌──────────┐    HTTP POST     │  stores messages │  │
│  │ Scripts  │ ────────────────►│                  │  │
│  │ Cron     │  App Token auth  │                  │  │
│  └──────────┘                  └────────┬─────────┘  │
│                                         │            │
│                                WebSocket│push        │
│                                         │            │
│                                ┌────────▼─────────┐  │
│                                │  Phone App       │  │
│                                │  (Gotify client) │  │
│                                │  Persistent       │  │
│                                │  background conn  │  │
│                                └──────────────────┘  │
└──────────────────────────────────────────────────────┘

Token types:
  APP TOKEN    = "I am allowed to SEND messages"     → give to senders
  CLIENT TOKEN = "I am allowed to RECEIVE messages"  → managed by phone app
  USER LOGIN   = "I am admin, I can do everything"   → web UI / API auth
```
