# Web Apps & Reverse Proxy — The Idiot's Guide

## What Is This?

You have two containers working together to serve web apps on your network:

```
┌──────────────────────────────────────────────────────────────────┐
│                        YOUR NETWORK                              │
│                                                                  │
│   Browser types: calc.home                                       │
│       │                                                          │
│       ▼                                                          │
│   Pi-hole DNS (LXC 110)                                         │
│       "calc.home → 192.168.68.53"                                │
│       │                                                          │
│       ▼                                                          │
│   ┌──────────────────────────────┐                               │
│   │  PROXY (LXC 114)            │                                │
│   │  192.168.68.53               │                                │
│   │  Nginx reverse proxy         │                                │
│   │                              │                                │
│   │  "calc.home? Route to        │                                │
│   │   webapps at .55"            │                                │
│   └──────────┬───────────────────┘                               │
│              │                                                   │
│              ▼                                                   │
│   ┌──────────────────────────────┐                               │
│   │  WEBAPPS (LXC 115)          │                                │
│   │  192.168.68.55               │                                │
│   │  Nginx web server            │                                │
│   │                              │                                │
│   │  /var/www/calc/index.html    │                                │
│   │  /var/www/tracker/index.html │  ← future apps go here        │
│   │  /var/www/whatever/          │                                │
│   └──────────────────────────────┘                               │
└──────────────────────────────────────────────────────────────────┘
```

### Why two containers instead of one?

The **proxy** is a traffic cop — it doesn't host anything itself. It looks at the
hostname in each request and forwards it to the right backend. This means:

- All your services (Gotify, BookStack, Pi-hole, your apps) get a single entry point
- When you add TLS (HTTPS) later, you do it in one place — the proxy
- Your app container doesn't need to know or care about certs, routing, or other services
- You can move, rebuild, or scale the webapps container without touching routing

The **webapps** container is a dumb web server — it just serves files. It doesn't
know or care that a proxy sits in front of it.

## How a Request Flows

```
1. You type "calc.home" in your browser

2. Browser asks Pi-hole: "What IP is calc.home?"
   Pi-hole answers: "192.168.68.53" (the proxy)

3. Browser sends HTTP request to 192.168.68.53:
   GET / HTTP/1.1
   Host: calc.home          ← this header is the key

4. Proxy Nginx receives the request, checks server blocks:
   "calc.home matches → proxy_pass to 192.168.68.55"

5. Proxy forwards the request to the webapps container,
   preserving the Host header

6. Webapps Nginx receives the request, checks server blocks:
   "calc.home matches → serve files from /var/www/calc/"

7. Webapps sends /var/www/calc/index.html back through the proxy to your browser
```

The key insight: **everything routes by hostname, not by port or path**. All traffic
goes to the same IP (the proxy) on port 80. The `Host` header in the HTTP request
is what tells Nginx where to send it.

## Where Everything Lives

### Container Overview

| Container | VMID | IP | Role | Key Config File |
|-----------|------|----|------|-----------------|
| proxy | 114 | 192.168.68.53 | Routes traffic | `/etc/nginx/sites-available/proxy` |
| webapps | 115 | 192.168.68.55 | Serves app files | `/etc/nginx/sites-available/apps` |
| pihole | 110 | 192.168.68.51 | DNS resolution | `/etc/pihole/pihole.toml` |

### Files You'll Edit

There are only **3 files** you ever need to touch, and they're on 3 different containers:

```
1. Pi-hole DNS config (LXC 110)
   /etc/pihole/pihole.toml → dns.hosts array
   "Tell the network that myapp.home points to the proxy"

2. Proxy Nginx config (LXC 114)
   /etc/nginx/sites-available/proxy
   "When you see myapp.home, forward to the webapps container"

3. Webapps Nginx config (LXC 115)
   /etc/nginx/sites-available/apps
   "When you see myapp.home, serve files from /var/www/myapp/"
```

## How to Add a New App

Let's say you want to add a budget tracker at `budget.home`.

### Step 1: Create the app files on the webapps container

```bash
# From the Proxmox host:
pct exec 115 -- mkdir -p /var/www/budget

# Push your files (from the Proxmox host):
pct push 115 /path/to/index.html /var/www/budget/index.html

# Or edit directly inside the container:
pct exec 115 -- bash
nano /var/www/budget/index.html
# ... write your HTML/JS/CSS ...
exit
```

### Step 2: Add a server block on the webapps container (LXC 115)

```bash
pct exec 115 -- bash
nano /etc/nginx/sites-available/apps
```

Add this block (copy-paste from an existing one and change the name + path):

```nginx
# budget.home — Budget Tracker
server {
    listen 80;
    server_name budget.home;

    root /var/www/budget;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Test and reload:

```bash
nginx -t                    # check for syntax errors
systemctl reload nginx      # apply without downtime
exit
```

### Step 3: Add a proxy route on the proxy container (LXC 114)

```bash
pct exec 114 -- bash
nano /etc/nginx/sites-available/proxy
```

Add this block (above the catch-all):

```nginx
# budget.home → webapps container
server {
    listen 80;
    server_name budget.home;

    location / {
        proxy_pass http://192.168.68.55;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Test and reload:

```bash
nginx -t
systemctl reload nginx
exit
```

### Step 4: Add DNS in Pi-hole (LXC 110)

```bash
pct exec 110 -- bash
nano /etc/pihole/pihole.toml
```

Find the `dns.hosts` array and add your entry. **Point it to the proxy IP (192.168.68.53),
NOT the webapps IP:**

```toml
  hosts = [
    "192.168.68.200 proxmox.home",
    "192.168.68.51 pihole.home",
    "192.168.68.58 samba.home",
    "192.168.68.59 gotify.home",
    "192.168.68.52 wiki.home",
    "192.168.68.53 proxy.home",
    "192.168.68.55 webapps.home",
    "192.168.68.53 calc.home",
    "192.168.68.53 budget.home"
  ]
```

Reload DNS:

```bash
/usr/local/bin/pihole reloaddns
exit
```

### Step 5: Test

```bash
# From any machine on the network:
curl -s http://budget.home/
# Should return your HTML

# Or just open http://budget.home in your browser
```

## How to Update an Existing App

Updating an app's files does NOT require touching Nginx or DNS. Just replace the files:

```bash
# From the Proxmox host — push updated files:
pct push 115 /path/to/new-index.html /var/www/calc/index.html

# Or edit in place:
pct exec 115 -- nano /var/www/calc/index.html
```

No reload needed — Nginx serves files from disk on every request. Changes are instant.

## How to Test

### Quick test from the command line

```bash
# Test DNS resolves (from any machine using Pi-hole):
getent hosts calc.home
# Expected: 192.168.68.53  calc.home

# Test the proxy routes correctly:
curl -s -o /dev/null -w "HTTP %{http_code}" http://calc.home/
# Expected: HTTP 200

# Test the webapps container directly (bypass proxy):
curl -s -o /dev/null -w "HTTP %{http_code}" -H "Host: calc.home" http://192.168.68.55/
# Expected: HTTP 200

# Test the full page content:
curl -s http://calc.home/ | head -5
# Expected: first 5 lines of your HTML
```

### Debugging a broken app

If something isn't working, test each layer in order:

```
Layer 1: DNS
    getent hosts myapp.home
    → No result? Pi-hole DNS entry missing or not reloaded

Layer 2: Proxy
    curl -s -o /dev/null -w "%{http_code}" http://192.168.68.53/ -H "Host: myapp.home"
    → 404? Proxy doesn't have a server block for myapp.home
    → 502? Proxy can't reach the webapps container (is it running?)

Layer 3: Webapps
    curl -s -o /dev/null -w "%{http_code}" http://192.168.68.55/ -H "Host: myapp.home"
    → 404? Webapps Nginx doesn't have a server block, OR the files don't exist
    → 403? Files exist but permissions are wrong

Layer 4: Files
    pct exec 115 -- ls -la /var/www/myapp/
    → Do the files exist? Is index.html there?
```

### Check Nginx status and logs

```bash
# Proxy container (114):
pct exec 114 -- systemctl status nginx
pct exec 114 -- tail -20 /var/log/nginx/error.log
pct exec 114 -- tail -20 /var/log/nginx/access.log

# Webapps container (115):
pct exec 115 -- systemctl status nginx
pct exec 115 -- tail -20 /var/log/nginx/error.log
pct exec 115 -- tail -20 /var/log/nginx/access.log
```

### Validate Nginx config without reloading

Always do this before reloading — a bad config will crash Nginx:

```bash
pct exec 114 -- nginx -t    # proxy
pct exec 115 -- nginx -t    # webapps
```

## Cheat Sheet

| Task | Command |
|------|---------|
| Shell into proxy | `pct exec 114 -- bash` |
| Shell into webapps | `pct exec 115 -- bash` |
| Edit proxy routes | `pct exec 114 -- nano /etc/nginx/sites-available/proxy` |
| Edit webapps sites | `pct exec 115 -- nano /etc/nginx/sites-available/apps` |
| Edit Pi-hole DNS | `pct exec 110 -- nano /etc/pihole/pihole.toml` |
| Reload proxy Nginx | `pct exec 114 -- systemctl reload nginx` |
| Reload webapps Nginx | `pct exec 115 -- systemctl reload nginx` |
| Reload Pi-hole DNS | `pct exec 110 -- /usr/local/bin/pihole reloaddns` |
| Test config (proxy) | `pct exec 114 -- nginx -t` |
| Test config (webapps) | `pct exec 115 -- nginx -t` |
| Push file to webapps | `pct push 115 local_file /var/www/appname/file` |
| Test from CLI | `curl -s http://appname.home/` |

## The Proxy Also Routes Existing Services

The proxy isn't just for your apps — it sits in front of everything:

```
calc.home      → 192.168.68.55 (webapps, LXC 115)
gotify.home    → 192.168.68.59 (gotify, LXC 112)  — includes WebSocket support
wiki.home      → 192.168.68.52 (bookstack, LXC 113)
pihole.home    → 192.168.68.51 (pihole, LXC 110)
```

Right now these services still have their DNS pointing directly to their container IPs.
To route them through the proxy instead, update their Pi-hole DNS entries to point to
192.168.68.53 (the proxy). The proxy server blocks for them are already configured.

**Note:** Don't change Pi-hole's own DNS entry to point at the proxy — that would create
a circular dependency (DNS needs to resolve to reach the proxy, but the proxy needs DNS).
Keep `pihole.home` pointing directly at `192.168.68.51`.

## Future: Adding HTTPS (TLS)

When you're ready to add HTTPS, you'll only need to change the **proxy** container:

1. Install certbot or use self-signed certs on LXC 114
2. Update proxy server blocks to listen on 443 with SSL
3. Add a redirect from 80 → 443
4. Backend containers stay on plain HTTP — the proxy terminates TLS

The webapps container and all backend services never need to know about HTTPS.
This is called **TLS termination** — encryption ends at the proxy, and internal
traffic stays plain HTTP (which is fine on a trusted LAN).

## Architecture Recap

```
┌─────────────────────────────────────────────────────────────┐
│                     Traffic Flow                             │
│                                                              │
│  Browser                                                     │
│    │                                                         │
│    │  "calc.home"                                            │
│    ▼                                                         │
│  Pi-hole (110) ──DNS──▶ 192.168.68.53                        │
│    │                                                         │
│    ▼                                                         │
│  Proxy (114) ──────────▶ Webapps (115)                       │
│    │  checks Host          /var/www/calc/                     │
│    │  header               /var/www/budget/                   │
│    │                       /var/www/.../                      │
│    │                                                         │
│    ├──────────────────▶ Gotify (112)                         │
│    ├──────────────────▶ BookStack (113)                      │
│    └──────────────────▶ Pi-hole (110)                        │
│                                                              │
│  All routing decisions based on the Host header.             │
│  All DNS entries point to the proxy (except pihole.home).    │
│  Backend services don't know the proxy exists.               │
└─────────────────────────────────────────────────────────────┘
```
