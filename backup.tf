# Backup Job Configurations
# All backups use 'local' (dir-type storage) which supports backup content type
# DO NOT use 'local-zfs' (ZFS pool) for backups - it does NOT support backup content type
# Schedules use systemd calendar format: https://www.freedesktop.org/software/systemd/man/systemd.time.html#Calendar%20Event

# Home Assistant VM (100) - Daily 21:00
# Commented out - backup job needs to be recreated
resource "proxmox_backup_job" "home_assistant" {
  id       = "home-assistant-backup"
  schedule  = "*-*-* 21:00"
  storage   = "local"
  vmid      = ["100"]
  mode      = "snapshot"
  compress  = "zstd"
  enabled   = true
  
  # Keep last 5 backups
  prune_backups = {
    keep-last = "5"
  }

  mailnotification = "failure"
  mailto           = ["root"]
}

# Docker container (101) - Daily 03:00 (off-peak, no contention)
# Excluded /data (media + torrents) via null_resource workaround below
# Reason: provider bpg/proxmox v0.106.0 has a bug with PVE 9.x API returning
# exclude-path as JSON array instead of comma-separated string. This will be
# simplified once the provider fixes it.
resource "proxmox_backup_job" "docker" {
  id       = "docker-backup"
  schedule  = "*-*-* 03:00"
  storage   = "local"
  vmid      = ["101"]
  mode      = "snapshot"
  compress  = "zstd"
  enabled   = true
  
  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
  
  mailnotification = "failure"
  mailto           = ["root"]
}

# Workaround: bpg/proxmox provider can't handle exclude-path on PVE 9.x API
# Sets it via Proxmox CLI after any change to the backup job
resource "null_resource" "docker_backup_exclude" {
  triggers = {
    backup_job_id = proxmox_backup_job.docker.id
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 'pvesh set /cluster/backup/docker-backup --exclude-path /data >/dev/null 2>&1'"
  }
}

# Tailscale container (102) - Daily 03:45 (after CT 101)
resource "proxmox_backup_job" "tailscale" {
  id       = "tailscale-backup"
  schedule  = "*-*-* 03:45"
  storage   = "local"
  vmid      = ["102"]
  mode      = "snapshot"
  compress  = "zstd"
  enabled   = true
  
  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
  
  mailnotification = "failure"
  mailto           = ["root"]
}

# AdGuard container (103) - Daily 04:00 (after CT 102)
resource "proxmox_backup_job" "adguard" {
  id       = "adguard-backup"
  schedule  = "*-*-* 04:00"
  storage   = "local"
  vmid      = ["103"]
  mode      = "snapshot"
  compress  = "zstd"
  enabled   = true
  
  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
  
  mailnotification = "failure"
  mailto           = ["root"]
}

# --- Disk monitoring ---
# Deploys check-backup-disk.sh and installs a cron job on the Proxmox host.
# Runs hourly, logs to syslog, and emails root on warnings (>=80%) or criticals (>=90%).

resource "null_resource" "deploy_disk_monitor" {
  triggers = {
    script_hash = filesha256("scripts/check-backup-disk.sh")
  }

  provisioner "local-exec" {
    command = <<-EOC
      scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no \
        scripts/check-backup-disk.sh \
        root@192.168.1.134:/usr/local/bin/check-backup-disk.sh && \
      ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
        'chmod 755 /usr/local/bin/check-backup-disk.sh && \
         echo "*/60 * * * * root /usr/local/bin/check-backup-disk.sh -w 80 -c 90" >/etc/cron.d/check-backup-disk'
    EOC
  }
}
