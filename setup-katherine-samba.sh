#!/usr/bin/env bash
#
# Set up the Proxmox Samba mounts on Katherine's Fedora 44 laptop.
# Mirrors Scoot's laptop setup: CIFS via fstab with x-systemd.automount,
# pointing at the shares by IP (not .home DNS) so a Pi-hole/host outage
# can't break them.
#
# Sets up two mounts:
#   /mnt/backup/katherine -> //192.168.68.58/katherine  (private, password)
#   /mnt/backup/public    -> //192.168.68.58/public     (shared, guest/no auth)
#
# Run on HER laptop, logged in as HER normal user:
#     sudo ./setup-katherine-samba.sh
#
set -euo pipefail

SERVER_IP="192.168.68.58"
HOST_IP="192.168.68.200"

# --- sanity checks --------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi

# The local account that should own the mounts (the person who ran sudo).
LOCAL_USER="${SUDO_USER:-}"
if [[ -z "$LOCAL_USER" || "$LOCAL_USER" == "root" ]]; then
    echo "Run this via 'sudo' from Katherine's normal user account, not as root directly." >&2
    exit 1
fi
LOCAL_UID="$(id -u "$LOCAL_USER")"
LOCAL_GID="$(id -g "$LOCAL_USER")"
echo "Setting up mounts for local user '$LOCAL_USER' (uid=$LOCAL_UID, gid=$LOCAL_GID)"

# --- 1. cifs-utils --------------------------------------------------------
if ! rpm -q cifs-utils >/dev/null 2>&1; then
    echo "Installing cifs-utils..."
    dnf install -y cifs-utils
else
    echo "cifs-utils already installed."
fi

install -d -m 700 /etc/samba

# --- helper: add one CIFS mount to fstab and activate its automount -------
# Usage: setup_mount <share-name> <mountpoint> <extra-mount-opts>
setup_mount() {
    local share_name="$1" mountpoint="$2" extra_opts="$3"
    local share="//$SERVER_IP/$share_name"
    local fstab_line="$share $mountpoint cifs ${extra_opts},uid=$LOCAL_UID,gid=$LOCAL_GID,x-systemd.automount,x-systemd.idle-timeout=60,_netdev,noauto 0 0"

    install -d -o "$LOCAL_USER" -g "$LOCAL_GID" "$mountpoint"

    if grep -qF " $mountpoint " /etc/fstab; then
        echo "An fstab entry for $mountpoint already exists — leaving it alone:"
        grep -F " $mountpoint " /etc/fstab
    else
        cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
        printf '%s\n' "$fstab_line" >> /etc/fstab
        echo "Added fstab entry for $share:"
        echo "  $fstab_line"
    fi

    systemctl daemon-reload
    local unit
    unit="$(systemd-escape -p --suffix=automount "$mountpoint")"
    systemctl start "$unit"

    if timeout 15 ls "$mountpoint" >/dev/null 2>&1; then
        echo "✅ $share mounts on access at $mountpoint"
    else
        echo "⚠️  Could not confirm access to $share at $mountpoint — check that the"
        echo "    Samba LXC (111) on $HOST_IP is up (and the password, for private shares)."
    fi
    echo
}

# --- 2. private share (katherine) -----------------------------------------
# Prompt for the Samba password (never store it in the script / git).
# NOTE: written with printf and NO trailing spaces — a trailing space on the
# username line previously caused STATUS_LOGON_FAILURE.
CREDS="/etc/samba/katherine-credentials"
read -rsp "Enter Samba password for user 'katherine': " SMB_PASS
echo
if [[ -z "$SMB_PASS" ]]; then
    echo "Password was empty, aborting." >&2
    exit 1
fi
printf 'username=%s\npassword=%s\n' "katherine" "$SMB_PASS" > "$CREDS"
chmod 600 "$CREDS"
unset SMB_PASS
echo "Wrote credentials to $CREDS (mode 600)."
echo

setup_mount "katherine" "/mnt/backup/katherine" "credentials=$CREDS"

# --- 3. public/shared share -----------------------------------------------
# Despite the name, 'public' is NOT a guest share — it has valid users =
# @samba-users, so it needs an authenticated user in that group. Katherine
# is a member, so we mount it with the same credentials as her private share.
# file_mode/dir_mode so files land group-writable for sharing between users.
setup_mount "public" "/mnt/backup/public" "credentials=$CREDS,file_mode=0664,dir_mode=0775"

echo "All done."
echo "  Private: /mnt/backup/katherine"
echo "  Shared:  /mnt/backup/public"
