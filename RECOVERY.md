# Homelab HP136 - Recovery Procedures

This document describes how to recover from various disasters in your Proxmox homelab.

## Backup Locations

All backups use `local` (dir-type storage) at `/var/lib/vz/dump/`. ZFS pool storage (`local-zfs`) does NOT support backup content type.

| Resource | Backup Schedule | Storage | Retention Policy |
|-----------|----------------|---------|------------------|
| VM 100 (Home Assistant) | Daily 21:00 | local (dir) | Keep last 5 |
| Container 101 (docker) | Daily 03:00 | local (dir) | Keep daily + monthly (excludes `/data`) |
| Container 102 (tailscale) | Daily 03:45 | local (dir) | Keep daily + monthly |
| Container 103 (adguard) | Daily 04:00 | local (dir) | Keep daily + monthly |

**Note:** Docker backup excludes `/data` (media + torrents) — those are replaceable via \*arr downloads. Schedules are staggered off-peak to avoid I/O contention.

## Restore Procedures

### Restore VM 100 (Home Assistant)

1. **List available backups:**
   ```bash
   ssh root@192.168.1.134 "ls -lh /var/lib/vz/dump/vzdump-qemu-100*"
   ```

2. **Restore VM (will create new VMID):**
   ```bash
   ssh root@192.168.1.134 "qmrestore <backup-file>.vma.zst <new-vmid>"
   ```

3. **Or restore to existing VM 100 (destructive):**
   ```bash
   ssh root@192.168.1.134 "qmrestore <backup-file>.vma.zst 100 --force"
   ```

4. **After restore, re-configure USB passthrough:**
   ```bash
   ssh root@192.168.1.134 "qm set 100 -usb0 host=10c4:ea60 -usb1 host=0bda:c821"
   ```

### Restore Container 101 (docker)

1. **List available backups:**
   ```bash
   ssh root@192.168.1.134 "ls -lh /var/lib/vz/dump/vzdump-lxc-101-*"
   ```

2. **Restore container (replace target VMID if needed):**
   ```bash
   ssh root@192.168.1.134 "pct restore 101 /var/lib/vz/dump/vzdump-lxc-101-*.vma.zst --storage local-zfs"
   ```

3. **Post-restore: Re-apply LXC 101 specific config not preserved in backup:**
   ```bash
   # Re-enable device passthrough (iGPU)
   pct set 101 -dev0 /dev/dri/card0,uid=0,gid=0,mode=0666
   pct set 101 -dev1 /dev/dri/renderD128,uid=0,gid=0,mode=0666

   # Re-add /data bind mount if missing
   pct set 101 -mp0 /data,mp=/data
   ```

4. **Restart Docker stack (managed via Arcane):**
   ```bash
   pct exec 101 -- docker compose -f /root/docker/arcane/compose.yml up -d
   ```

### Restore Container 102 (tailscale) / 103 (adguard)

Same procedure as docker:
```bash
# List backups
ssh root@192.168.1.134 "ls -lh /var/lib/vz/dump/vzdump-lxc-<vmid>-*"

# Restore
ssh root@192.168.1.134 "pct restore <vmid> /var/lib/vz/dump/vzdump-lxc-<vmid>-*.vma.zst --storage local-zfs"
```

## Disaster Recovery Scenarios

### Scenario 1: Proxmox Host Failure (prxhp136)

1. **Reinstall Proxmox VE** on new hardware
2. **Restore from Terraform** (the infrastructure is fully defined in code):
   ```bash
   cd ~/homelab-terraform
   terraform init
   terraform apply  # This will recreate containers from scratch
   ```
3. **Restore critical data from backups:**
   ```bash
   # Restore Home Assistant VM from backup
   ssh root@new-host "qmrestore /var/lib/vz/dump/vzdump-qemu-100-*.vma.zst 100 --force"

   # Restore docker container data (if /data was backed up)
   ssh root@new-host "pct restore 101 /var/lib/vz/dump/vzdump-lxc-101-*.vma.zst --storage local-zfs"
   ```

### Scenario 2: Accidental Container/VM Deletion

1. **Check backups immediately:**
   ```bash
   ssh root@192.168.1.134 "ls -lh /var/lib/vz/dump/ | grep <vmid>"
   ```
2. **Restore from most recent backup** (see procedures above)

### Scenario 3: Configuration Drift

If Terraform state drifts from actual:

1. **Refresh state:**
   ```bash
   cd ~/homelab-terraform
   terraform refresh
   terraform plan  # Review detected changes
   ```
2. **Import missing resources:**
   ```bash
   terraform import proxmox_virtual_environment_container.docker prxhp136/101
   ```
3. **Or destroy and recreate (DOWNTIME!):**
   ```bash
   terraform destroy -target=proxmox_virtual_environment_container.docker
   terraform apply
   ```

## Backup Cleanup Script

**Location:** `/usr/local/bin/cleanup-backups.sh`

**Retention Policy:** 
- **Current month:** Keep ALL daily backups
- **Previous months:** Keep ONLY the LAST backup (highest date) of each month

**Manual execution:**
```bash
ssh root@192.168.1.134 "/usr/local/bin/cleanup-backups.sh"
```

**Scheduled:** Daily at 1:00 AM via cron

**Log file:** `/var/log/backup-cleanup.log`

## Emergency Contacts

- **Owner:** @Darth-ATA
- **Location:** ~/homelab-terraform on GitHub
- **Proxmox Web UI:** https://192.168.1.134:8006

## Quick Reference

| Service | VMID | IP (Static) | Purpose |
|----------|------|-------------|---------|
| Home Assistant | 100 | 192.168.1.100 | Home automation |
| docker | 101 | 192.168.1.142 | Container runtime + media stack |
| tailscale | 102 | 192.168.1.102 | VPN network |
| adguard | 103 | 192.168.1.2 | DNS ad-blocking |

## Prevention Tips

1. **Test backups regularly:** Restore to a test VMID monthly
2. **Document changes:** Update README.md, NETWORK.md, and this file after any infra change
3. **Use Terraform:** All containers and VMs are defined in `.tf` files — never create infra manually
4. **Monitor backups:** Check `/var/log/backup-cleanup.log` regularly
5. **Keep this repo in sync:** If you change something on Proxmox, update the corresponding `.tf` file and run `terraform plan` to verify state
