# Monitoring and Backup Cleanup Scripts
# Deploys host-level monitoring scripts and cron jobs to the Proxmox host.
# Scripts manage backup disk usage alerts, backup job status checks, and
# old backup cleanup.
#
# All scripts live in scripts/ and are deployed via null_resource + local-exec.

locals {
  cleanup_backups_hash    = filebase64sha256("${path.module}/scripts/cleanup-backups.sh")
  check_backup_disk_hash  = filebase64sha256("${path.module}/scripts/check-backup-disk.sh")
  check_backup_status_hash = filebase64sha256("${path.module}/scripts/check-backup-status.sh")
}

# ─── Script Deployment ─────────────────────────────────────────────────────────

resource "null_resource" "deploy_cleanup_backups" {
  triggers = {
    script_hash = local.cleanup_backups_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/cleanup-backups.sh root@${var.proxmox_host_ip}:/usr/local/bin/cleanup-backups.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/cleanup-backups.sh'
EOT
  }
}

resource "null_resource" "deploy_check_backup_disk" {
  triggers = {
    script_hash = local.check_backup_disk_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/check-backup-disk.sh root@${var.proxmox_host_ip}:/usr/local/bin/check-backup-disk.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/check-backup-disk.sh'
EOT
  }
}

resource "null_resource" "deploy_check_backup_status" {
  triggers = {
    script_hash = local.check_backup_status_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/check-backup-status.sh root@${var.proxmox_host_ip}:/usr/local/bin/check-backup-status.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/check-backup-status.sh'
EOT
  }
}

# ─── Cron Jobs ─────────────────────────────────────────────────────────────────

# Cleanup cron: runs BEFORE backup window (01:00) to prune backups from previous
# cycles, and AFTER backup window (05:00) to clean up the newly created backup.
# This dual schedule prevents the /var/lib/vz/dump directory from filling up
# during the backup window (03:00-04:30).

resource "null_resource" "backup_cleanup_cron" {
  triggers = {
    cron_spec = "cleanup-backups at 01:00 and 05:00 daily"
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
# Add pre-backup cleanup at 01:00 if not present
if ! crontab -l 2>/dev/null | grep -q "01:00.*cleanup-backups"; then
  (crontab -l 2>/dev/null; echo "0 1 * * * /usr/local/bin/cleanup-backups.sh") | crontab -
fi
# Add post-backup cleanup at 05:00 if not present
if ! crontab -l 2>/dev/null | grep -q "05:00.*cleanup-backups"; then
  (crontab -l 2>/dev/null; echo "0 5 * * * /usr/local/bin/cleanup-backups.sh") | crontab -
fi
REMOTE
EOT
  }
}

# Backup alert cron: checks disk usage every 60 minutes and backup status
# after the backup window ends (05:30). Alerts via Telegram on issues.

resource "null_resource" "backup_alert_crons" {
  triggers = {
    cron_spec = "check-backup-disk every 60min, check-backup-status at 05:30"
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
cat > /etc/cron.d/backup-alerts << 'CRONEOF'
# Backup status check — runs after backup window ends (last backup at 04:30)
30 5 * * * root /usr/local/bin/check-backup-status.sh

# Backup disk usage check — every 60 minutes
*/60 * * * * root /usr/local/bin/check-backup-disk.sh -w 80 -c 90
CRONEOF
chmod 644 /etc/cron.d/backup-alerts
REMOTE
EOT
  }
}

# ─── LXC Internet Connectivity Check ───────────────────────────────────────────
# Monitors internet access FROM inside LXC 101 (Docker host). Catches router-level
# blocks by EX520v DoS Protection that affect specific container IPs.
# Uses retry + consecutive-failure threshold to avoid false positives on transients.

locals {
  check_lxc_internet_hash = filebase64sha256("${path.module}/scripts/check-lxc-internet.sh")
}

resource "null_resource" "deploy_check_lxc_internet" {
  triggers = {
    script_hash = local.check_lxc_internet_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/check-lxc-internet.sh root@${var.proxmox_host_ip}:/usr/local/bin/check-lxc-internet.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/check-lxc-internet.sh'
EOT
  }
}

resource "null_resource" "lxc_internet_check_cron" {
  triggers = {
    cron_spec = "check-lxc-internet every 5 minutes"
    depends_on_script = local.check_lxc_internet_hash
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
# Remove legacy root crontab entry + comment (if migrating from manual setup)
if crontab -l 2>/dev/null | grep -q "check-lxc-internet\|LXC 101 internet"; then
  crontab -l 2>/dev/null | grep -v "check-lxc-internet\|LXC 101 internet" | crontab -
fi

# Write cron.d entry (system-wide, survives reboot)
cat > /etc/cron.d/lxc-internet-check << 'CRONEOF'
# LXC 101 internet connectivity check — every 5 minutes
# Catches EX520v DoS blocks that affect specific container IPs
*/5 * * * * root /usr/local/bin/check-lxc-internet.sh
CRONEOF
chmod 644 /etc/cron.d/lxc-internet-check
REMOTE
EOT
  }
}

# ─── ZFS Quota on Backup Storage ──────────────────────────────────────────────
# Sets a 40G quota on rpool/var-lib-vz to cap backup storage before the pool
# fills up. The monitoring script reads this quota to calculate usage %.

resource "null_resource" "backup_storage_zfs_quota" {
  triggers = {
    dataset = "rpool/var-lib-vz"
    quota   = "40G"
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'zfs set quota=40G rpool/var-lib-vz'
EOT
  }
}
