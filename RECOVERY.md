# Homelab HP136 - Recovery Procedures

This document describes how to recover from various disasters in your Proxmox homelab.

## Backup Locations

| Resource | Backup Schedule | Storage | Retention Policy |
|-----------|----------------|---------|------------------|
| VM 100 (Home Assistant) | Daily 21:00 | local (dir) | Last 3-5 backups |
| Container 101 (docker) | Daily 22:00 | local-zfs (ZFS) | **Keep daily, but only last of each month** |
| Container 102 (tailscale) | Daily 22:30 | local-zfs (ZFS) | **Keep daily, but only last of each month** |
| Container 103 (adguard) | Daily 23:00 | local-zfs (ZFS) | **Keep daily, but only last of each month** |

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
   ssh root@192.168.1.134 "qm set 100 -usb0 host=10c4:ea60"
   ```

### Restore Container 101 (docker)

1. **List available backups:**
   ```bash
   ssh root@192.168.1.134 "ls -lh /var/lib/vz/snapshot/docker*"
   # Or check local-zfs storage
   ```

2. **Restore container:**
   ```bash
   ssh root@192.168.1.134 "pct restore 101 <storage>:backup/vzdump-lxc-101-*.vma.zst"
   ```

### Restore Container 102 (tailscale) / 103 (adguard)

Same procedure as docker:
```bash
ssh root@192.168.1.134 "pct restore <vmid> <storage>:backup/vzdump-lxc-<vmid>-*.vma.zst"
```

## Disaster Recovery Scenarios

### Scenario 1: Proxmox Host Failure (prxhp136)

1. **Reinstall Proxmox VE** on new hardware
2. **Restore cluster configuration:**
   ```bash
   # Copy /etc/pve/ from backup
   scp -r /backup/etc/pve/ root@new-host:/etc/pve/
   ```
3. **Restore VMs and containers** using procedures above
4. **Re-configure network:** Check `/etc/network/interfaces`

### Scenario 2: Accidental Container/VM Deletion

1. **Check backups immediately:**
   ```bash
   ssh root@192.168.1.134 "ls -lh /var/lib/vz/dump/ | grep <vmid>"
   ```
2. **Restore from most recent backup** (see procedures above)

### Scenario 3: Configuration Drift

If Terraform state drifts from actual:

1. **Import existing resources:**
   ```bash
   cd ~/homelab-terraform
   terraform import proxmox_virtual_environment_container.docker prxhp136/101
   # Repeat for other resources
   ```
2. **Or destroy and recreate (DOWNTIME!):**
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

| Service | VMID | IP (DHCP) | Purpose |
|----------|------|-----------|---------|
| Home Assistant | 100 | Check in UI | Home automation |
| docker | 101 | DHCP | Container runtime |
| tailscale | 102 | DHCP | VPN network |
| adguard | 103 | DHCP | DNS ad-blocking |
| debian-test | 105 | DHCP | Test container |

## Prevention Tips

1. **Test backups regularly:** Restore to a test VMID monthly
2. **Document changes:** Update README.md and this file
3. **Use Terraform:** For new containers, use `new-container-example.tf`
4. **Monitor backups:** Check `/var/log/backup-cleanup.log` regularly
