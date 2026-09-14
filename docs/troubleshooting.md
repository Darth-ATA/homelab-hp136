# Troubleshooting — Known Proxmox Bugs & Workarounds

This document captures bugs and edge cases encountered in this homelab that are not obvious from the code alone.

---

## 1. Web UI 401 "authentication failure" despite correct password

**Symptom:** Login to `https://192.168.1.134:8006` returns `authentication failure (401)`. SSH login (`ssh -i ~/.ssh/homelab_key root@192.168.1.134`) works fine.

**Cause:** The Proxmox Cluster File System (`pmxcfs`) has a bloated SQLite WAL file that prevents the `authkey` lock from being acquired. Long-running instances accumulate a `config.db-wal` file that grows far larger than the main `config.db`.

**Diagnose:**
```bash
# Check pvedaemon logs for the specific error
ssh root@192.168.1.134 "journalctl -u pvedaemon -n 10"

# Look for: cfs-lock 'authkey' error: got lock request timeout
```

**Fix:**

```bash
ssh root@192.168.1.134

# 1. Checkpoint and truncate the bloated WAL
sqlite3 /var/lib/pve-cluster/config.db 'PRAGMA wal_checkpoint(TRUNCATE);'

# 2. Restart pve-cluster (pmxcfs)
systemctl restart pve-cluster

# 3. Restart proxy to clear stale tickets
systemctl restart pveproxy
```

**Note:** After the restart, `unix_chkpwd: password check failed for user (root)` in logs means the CFS issue is resolved — the failure is now a genuine password mismatch.

---

## 2. Silent backup failures — LXC lock:mounted

**Symptom:** Backup jobs appear to run but vzdump never creates snapshots. Old backup files accumulate on disk without being pruned. Eventually the backup storage fills up.

**Diagnose:**
```bash
# Check if backup disk is filling unexpectedly
ssh root@192.168.1.134 "df -h /var/lib/vz/dump"

# Check for locked containers
ssh root@192.168.1.134 "pct list | grep locked"

# Check container config for lock:mounted
ssh root@192.168.1.134 "grep 'lock: mounted' /etc/pve/lxc/*.conf"
```

**Cause:** When an LXC container has bind mounts (e.g., `mp0: /rpool/data/media,mp=/data`), Proxmox automatically sets `lock: mounted` in the container config. This prevents `vzdump` from creating snapshots, causing `CT is locked (mounted)`. The backup fails silently.

**Consequence:** Failed backups are NOT pruned automatically. They accumulate forever, consuming disk space at `local` (dir) storage.

**Fix:**

```bash
# 1. Remove the stale lock
ssh root@192.168.1.134 "sed -i '/^lock: mounted/d' /etc/pve/lxc/<VMID>.conf"

# 2. Force a manual backup + prune to clear failed dumps
ssh root@192.168.1.134 "vzdump <VMID> --storage local --mode snapshot --prune-backups 'keep-daily=1,keep-monthly=1'"

# 3. Clean old failed backup files manually if needed
ssh root@192.168.1.134 "ls -lh /var/lib/vz/dump/vzdump-lxc-<VMID>-*"
ssh root@192.168.1.134 "rm /var/lib/vz/dump/vzdump-lxc-<VMID>-<old-date>_*.vma.*"
```

**Prevention:** After any Terraform change that touches LXC bind mounts, verify the container doesn't have a stale lock. Add a post-apply check in the `null_resource`.

**History:** This caused LXC 101 backups to fail silently from Jun 24 2026. Two failed backups (82GB + 78GB) consumed 160GB before discovery.

---

## 3. bpg/proxmox `exclude-path` parse error (PVE 9.x)

**Symptom:** `terraform plan` fails with an error parsing `exclude-path` on `proxmox_backup_job` resources. The API returns `exclude-path` as a JSON array but the provider expects `CustomCommaSeparatedList`.

**Cause:** `bpg/proxmox` v0.106.0 + PVE 9.x have a type mismatch on the `exclude-path` attribute. The Proxmox API returns it as `["path1", "path2"]` (JSON array), but the provider schema uses `CustomCommaSeparatedList` and can't parse it on refresh.

**Workaround (applied):** The docker backup job was removed from Terraform state and config. It continues to run on PVE with its existing schedule, managed directly via the Proxmox UI.

**If you need to re-import or manage it:**
```bash
# Check if provider is fixed first
terraform plan

# If still broken, keep managing manually via PVE
# The backup job is created and scheduled outside Terraform

# Re-import only when provider is confirmed fixed:
terraform import proxmox_backup_job.docker prxhp136/docker-backup
```

**Status:** The docker backup job is the only one affected (it has `exclude-path` for `/data`). All other backup jobs in `backup.tf` work fine.

**Related:** There's a similar issue with the `nodes` attribute on `proxmox_storage` directory-type resources (see `proxmox-storage.tf`).

---

## 4. Docker backup job orphaned from Terraform

**Symptom:** `backup.tf` has the docker backup job commented out with a note. The job still exists and runs on PVE, but Terraform doesn't manage it.

**Context:** See issue #3 above — the `exclude-path` provider bug forced us to remove it from Terraform.

**What happens if you run `terraform apply`:** Terraform will NOT delete the job (it's not in state). The job will continue running as configured in PVE.

**When to re-import:** Only after confirming `bpg/proxmox` has fixed the `exclude-path` parsing issue. Then uncomment the resource in `backup.tf` and run:
```bash
terraform import proxmox_backup_job.docker prxhp136/docker-backup
```
