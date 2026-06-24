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

  mailnotification = "failure"

  # Keep last 3-5 backups
  prune_backups = {
    keep-last = "5"
  }
}

# Docker container (101) - Daily 03:00 (off-peak, no contention)
# Managed manually via PVE until provider bpg/proxmox fixes PVE 9.x API compatibility.
# The API returns `exclude-path` as JSON array which the provider can't parse.
# Re-import when fixed: terraform import proxmox_backup_job.docker prxhp136/docker-backup

# Tailscale container (102) - Daily 03:45 (after CT 101)
resource "proxmox_backup_job" "tailscale" {
  id       = "tailscale-backup"
  schedule = "*-*-* 03:45"
  storage  = "local"
  vmid     = ["102"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  mailnotification = "failure"

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

  mailnotification = "failure"

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

  mailnotification = "failure"

  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
}

# Jellyfin container (105) - Daily 04:30 (after CT 104)
# NOTE: Import after creating LXC 105:
#   terraform import proxmox_backup_job.jellyfin prxhp136/jellyfin-backup
resource "proxmox_backup_job" "jellyfin" {
  id       = "jellyfin-backup"
  schedule = "*-*-* 04:30"
  storage  = "local"
  vmid     = ["105"]
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  mailnotification = "failure"

  # Daily + Last of each month
  prune_backups = {
    keep-daily   = "1"
    keep-monthly = "1"
  }
}
