#!/bin/bash
# Use the storage manager so protected backups and associated files are handled
# by Proxmox. Scope each prune to one known guest on the local backup store.
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
case "$#:${1:-}" in
    0:) dry_run=0; exec >> /var/log/backup-cleanup.log ;;
    1:--dry-run) dry_run=1 ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

for vmid in 100 101 102 103 104 105; do
    type=lxc
    [[ $vmid != 100 ]] || type=qemu
    printf '%s: checking %s %s\n' "$(date -Is)" "$type" "$vmid"
    pvesm prune-backups local --type "$type" --vmid "$vmid" \
        --keep-daily 7 --keep-monthly 6 --dry-run "$dry_run"
done
