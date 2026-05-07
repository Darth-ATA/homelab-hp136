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
  
  # Keep last 3-5 backups
  prune_backups = {
    keep-last = "5"
  }
}

# Docker container (101) - Daily 22:00
resource "proxmox_backup_job" "docker" {
  id       = "docker-backup"
  schedule  = "*-*-* 22:00"
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
}

# Tailscale container (102) - Daily 22:30
resource "proxmox_backup_job" "tailscale" {
  id       = "tailscale-backup"
  schedule  = "*-*-* 22:30"
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
}

# AdGuard container (103) - Daily 23:00
resource "proxmox_backup_job" "adguard" {
  id       = "adguard-backup"
  schedule  = "*-*-* 23:00"
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
}
