# Backup Job Configurations
# All backups use 'local' (dir-type storage) which supports backup content type
# DO NOT use 'local-zfs' (ZFS pool) for backups - it does NOT support backup content type
# Schedules use systemd calendar format: https://www.freedesktop.org/software/systemd/man/systemd.time.html#Calendar%20Event

# Home Assistant VM (100) - Daily 21:00
# Commented out - backup job needs to be recreated
resource "proxmox_backup_job" "home_assistant" {
  id       = "home-assistant-backup"
  schedule = "*-*-* 21:00"
  storage  = "local"
  vmid     = ["100"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  # Keep last 3-5 backups
  prune_backups = {
    keep-last = "5"
  }
}

# Docker container (101) - Daily 03:00 (off-peak, no contention)
# Excluded /data (media + torrents) via null_resource workaround below
# Reason: provider bpg/proxmox v0.106.0 has a bug with PVE 9.x API returning
# exclude-path as JSON array instead of comma-separated string. This will be
# simplified once the provider fixes it.
resource "proxmox_backup_job" "docker" {
  id       = "docker-backup"
  schedule = "*-*-* 03:00"
  storage  = "local"
  vmid     = ["101"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
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
  schedule = "*-*-* 03:45"
  storage  = "local"
  vmid     = ["102"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
}

# AdGuard container (103) - Daily 04:00 (after CT 102)
resource "proxmox_backup_job" "adguard" {
  id       = "adguard-backup"
  schedule = "*-*-* 04:00"
  storage  = "local"
  vmid     = ["103"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
}

# Vaultwarden container (104) - Daily 04:15 (after CT 103)
resource "proxmox_backup_job" "vaultwarden" {
  id       = "vaultwarden-backup"
  schedule = "*-*-* 04:15"
  storage  = "local"
  vmid     = ["104"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
}
