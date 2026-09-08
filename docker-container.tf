# Note: If "changing feature flags is only allowed for root@pam" error occurs:
# Option 1: Remove features block (if present)
# Option 2: Import existing container with: terraform import proxmox_virtual_environment_container.docker prxhp136/101
resource "proxmox_virtual_environment_container" "docker" {
  node_name    = "prxhp136"
  vm_id        = 101
  started      = true
  unprivileged = false

  description = "Docker host: media stack + NPM + Arcane (2 cores, 6GB RAM, 150GB disk, iGPU passthrough)"

  tags = ["community-script", "os"]

  initialization {
    hostname = "docker"
    ip_config {
      ipv4 {
        address = "192.168.1.142/24"
        gateway = "192.168.1.1"
      }
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 6144
    swap      = 512
  }

  disk {
    datastore_id = "local-zfs"
    size         = 150
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "BC:24:11:C5:96:4F"
    firewall    = true
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  features {
    fuse    = false
    keyctl  = true
    mknod   = false
    mount   = []
    nesting = true
  }

  device_passthrough {
    path       = "/dev/dri/card0"
    uid        = 0
    gid        = 0
    mode       = "0666"
    deny_write = false
  }

  device_passthrough {
    path       = "/dev/dri/renderD128"
    uid        = 0
    gid        = 0
    mode       = "0666"
    deny_write = false
  }

  lifecycle {
    ignore_changes = [
      operating_system,
      unprivileged,
      vm_id,
      features,
      mount_point,
    ]
  }
}

# Mount point: LXC 101 shared media bind mount (shared ZFS dataset with LXC 105)
# Moves /data/media from subvol-101-disk-1 to dedicated rpool/data/media dataset
resource "null_resource" "docker_media_mount_point" {
  triggers = {
    container_id = 101
    mount_spec   = "/rpool/data/media,mp=/data/media"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct set 101 -mp0 /rpool/data/media,mp=/data/media'"
  }
}

# Mount point: LXC 101 torrents bind mount (dedicated ZFS dataset)
# Moves /data/torrents from subvol-101-disk-1 to dedicated rpool/data/torrents dataset
resource "null_resource" "docker_torrents_mount_point" {
  triggers = {
    container_id = 101
    mount_spec   = "/rpool/data/torrents,mp=/data/torrents"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct set 101 -mp1 /rpool/data/torrents,mp=/data/torrents'"
  }
}

# Mount point: LXC 101 soulseek bind mount (dedicated ZFS dataset)
# Moves /data/soulseek from subvol-101-disk-1 to dedicated rpool/data/soulseek dataset
resource "null_resource" "docker_soulseek_mount_point" {
  triggers = {
    container_id = 101
    mount_spec   = "/rpool/data/soulseek,mp=/data/soulseek"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct set 101 -mp2 /rpool/data/soulseek,mp=/data/soulseek'"
  }
}

# Docker image prune cron job: removes unused Docker images older than 72h every 2 weeks
# Keeps the last 3 days of images available for rollback while preventing image bloat
resource "null_resource" "docker_prune_cron" {
  triggers = {
    container_id = 101
    cron_spec    = "docker image prune -a --filter until=72h every 14 days"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct exec 101 -- sh -c \"echo \\\"0 3 */14 * * root docker image prune -a --filter until=72h --force\\\" > /etc/cron.d/docker-prune && chmod 644 /etc/cron.d/docker-prune\"'"
  }
}

# DARTH-GAIN Hevy sync cron: runs daily at 06:00 to sync Hevy workout data
# for all users who have an API key configured in DARTH-GAIN
resource "null_resource" "darth_gain_hevy_sync_cron" {
  triggers = {
    container_id = 101
    cron_spec    = "0 6 * * * DARTH_GAIN_DATA_DIR=/data /root/DARTH-GAIN/.venv/bin/python /root/DARTH-GAIN/scripts/cron-sync-all.py"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct exec 101 -- sh -c \"(crontab -u root -l 2>/dev/null | grep -v cron-sync-all.py; echo \\\"0 6 * * * DARTH_GAIN_DATA_DIR=/data /root/DARTH-GAIN/.venv/bin/python /root/DARTH-GAIN/scripts/cron-sync-all.py >> /var/log/darth-gain-sync.log 2>&1\\\") | crontab -u root -\"'"
  }
}

# Soularr config: ensure failed_import_denylist=True to prevent infinite re-download loops
# When failed_import_denylist=False (default), albums that fail Lidarr import are
# re-downloaded on every soularr run, creating infinite copies (observed: 55 copies of one album)
resource "null_resource" "soularr_failed_import_denylist" {
  triggers = {
    container_id = 101
    setting      = "failed_import_denylist = True"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct exec 101 -- sed -i \"s/^failed_import_denylist = .*/failed_import_denylist = True/\" /root/docker/soularr/config/config.ini'"
  }
}

# Bazarr: set minimum_score to 60 so lower-score subtitles (Spanish, etc.) are accepted
# Default 90 is too restrictive for many non-English subs; 60 matches common community configs
# The Bazarr container must be restarted after config change
resource "null_resource" "bazarr_minimum_score" {
  triggers = {
    container_id = 101
    setting      = "minimum_score = 60"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct exec 101 -- sh -c \"sed -i \\\"s/^  minimum_score: [0-9]*/  minimum_score: 60/\\\" /root/docker/bazarr/config/config/config.yaml && docker restart bazarr\"'"
  }
}
