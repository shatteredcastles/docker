#!/bin/bash
# Nightly copy of the Proxmox host's own configuration to the Synology.
# Guests are backed up by the Proxmox backup jobs; this covers the host itself
# (cluster config, network, GPU passthrough, NUT, Tailscale) so a rebuild is
# "reinstall Proxmox, then restore these files".
#
# Installed at /usr/local/sbin/pve-config-backup.sh on pve, run from
# /etc/cron.d/pve-config-backup. Output: /mnt/pve/synology/host-config/.
#
# The archive contains secrets (Proxmox keys, Tailscale node key), so the
# folder is root-only.
set -euo pipefail

DEST_ROOT=/mnt/pve/synology
DEST="$DEST_ROOT/host-config"
KEEP=30
STAMP=$(date +%Y%m%d-%H%M)
ARCHIVE="$DEST/pve-config-$STAMP.tar.gz"

log() { logger -t pve-config-backup "$*"; echo "$*"; }

if ! mountpoint -q "$DEST_ROOT"; then
    log "ERROR: $DEST_ROOT is not mounted, skipping"
    exit 1
fi
mkdir -p "$DEST"
chmod 700 "$DEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Lists that make a rebuild easier to check against
dpkg --get-selections > "$TMP/dpkg-selections.txt"
pveversion -v > "$TMP/pveversion.txt"
qm list > "$TMP/qm-list.txt"
pct list > "$TMP/pct-list.txt"
zpool status > "$TMP/zpool-status.txt"
cat /proc/cmdline > "$TMP/proc-cmdline.txt"

PATHS=(
    /etc/pve                          # VM/CT configs, storage, backup jobs, users
    /var/lib/pve-cluster/config.db    # database behind /etc/pve
    /etc/network/interfaces
    /etc/network/if-up.d
    /etc/hosts /etc/hostname /etc/resolv.conf /etc/fstab
    /etc/kernel/cmdline               # intel_iommu=on iommu=pt
    /etc/modules /etc/modprobe.d      # vfio-pci binding, i915/xe blacklist
    /etc/sysctl.d
    /etc/nut                          # UPS server
    /var/lib/tailscale                # Tailscale node identity
    /etc/apt/sources.list.d
    /root/.ssh
    /usr/local/sbin
    /etc/cron.d
)
existing=()
for p in "${PATHS[@]}"; do [ -e "$p" ] && existing+=("$p"); done

tar -czf "$ARCHIVE" --absolute-names "${existing[@]}" -C "$TMP" . 2>"$TMP/tar.err" || {
    # tar exits 1 if a file changed while being read (e.g. config.db); keep the archive
    [ $? -eq 1 ] || { log "ERROR: tar failed: $(tail -1 "$TMP/tar.err")"; exit 1; }
}
chmod 600 "$ARCHIVE"

# Keep the newest $KEEP archives
ls -1t "$DEST"/pve-config-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

log "OK: $(basename "$ARCHIVE") ($(du -h "$ARCHIVE" | cut -f1)), $(ls "$DEST"/pve-config-*.tar.gz | wc -l) kept"
