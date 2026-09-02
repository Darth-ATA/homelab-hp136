# ============================================================
# CLEANUP AUTOMATION — Space management via Terraform
# ============================================================
# Pattern: Deploy scripts from scripts/cleanup/ then install cron
# All cleanup runs on Proxmox host or inside LXC containers
# ============================================================

# ----------------------------------------------------------------------
# BACKUP CLEANUP — Deploy improved script (replaces existing in monitoring.tf)
# ----------------------------------------------------------------------

resource "null_resource" "deploy_backup_cleanup_script" {
  triggers = {
    script_version = "v2-7daily-6monthly"
  }

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no scripts/cleanup/cleanup-backups.sh root@${local.host_ip}:/usr/local/bin/cleanup-backups.sh && ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'chmod +x /usr/local/bin/cleanup-backups.sh'"
  }
}

# The backup cleanup cron already exists in monitoring.tf (runs at 01:00 and 05:00)
# It will automatically use the new script deployed above.

# ----------------------------------------------------------------------
# TORRENT CLEANUP — Deluge seeding management
# ----------------------------------------------------------------------

resource "null_resource" "deploy_torrent_cleanup_script" {
  triggers = {
    script_version = "v1-ratio2-age30-size10"
  }

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no scripts/cleanup/cleanup-torrents.sh root@${local.host_ip}:/usr/local/bin/cleanup-torrents.sh && ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'chmod +x /usr/local/bin/cleanup-torrents.sh'"
  }
}

resource "null_resource" "torrent_cleanup_cron" {
  triggers = {
    container_id = 101
    cron_spec    = "torrent cleanup daily at 02:00"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 101 -- sh -c \"echo \\\"0 2 * * * root /usr/local/bin/cleanup-torrents.sh\\\" > /etc/cron.d/torrent-cleanup && chmod 644 /etc/cron.d/torrent-cleanup\"'"
  }
}

# ----------------------------------------------------------------------
# SOULSEEK CLEANUP — slskd downloads & failed_imports
# ----------------------------------------------------------------------

resource "null_resource" "deploy_soulseek_cleanup_script" {
  triggers = {
    script_version = "v1-incomplete7-failed14"
  }

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no scripts/cleanup/cleanup-soulseek.sh root@${local.host_ip}:/usr/local/bin/cleanup-soulseek.sh && ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'chmod +x /usr/local/bin/cleanup-soulseek.sh'"
  }
}

resource "null_resource" "soulseek_cleanup_cron" {
  triggers = {
    container_id = 101
    cron_spec    = "soulseek cleanup daily at 03:00"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 101 -- sh -c \"echo \\\"0 3 * * * root /usr/local/bin/cleanup-soulseek.sh\\\" > /etc/cron.d/soulseek-cleanup && chmod 644 /etc/cron.d/soulseek-cleanup\"'"
  }
}

# ----------------------------------------------------------------------
# DOCKER VOLUME PRUNE — Additional safety
# ----------------------------------------------------------------------

resource "null_resource" "docker_volume_prune_cron" {
  triggers = {
    container_id = 101
    cron_spec    = "docker volume prune monthly"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 101 -- sh -c \"echo \\\"0 4 1 * * root docker volume prune -f --filter label!=keep\\\" > /etc/cron.d/docker-volume-prune && chmod 644 /etc/cron.d/docker-volume-prune\"'"
  }
}

# ----------------------------------------------------------------------
# JELLYFIN CACHE CLEANUP — Transcode cache & metadata
# ----------------------------------------------------------------------

resource "null_resource" "deploy_jellyfin_cleanup_script" {
  triggers = {
    script_version = "v1-cache3-metadata30"
  }

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no scripts/cleanup/cleanup-jellyfin.sh root@${local.host_ip}:/usr/local/bin/cleanup-jellyfin.sh && ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'chmod +x /usr/local/bin/cleanup-jellyfin.sh'"
  }
}

resource "null_resource" "jellyfin_cache_cleanup_cron" {
  triggers = {
    container_id = 105
    cron_spec    = "jellyfin cache cleanup weekly Sunday 04:00"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 105 -- sh -c \"echo \\\"0 4 * * 0 root /usr/local/bin/cleanup-jellyfin.sh\\\" > /etc/cron.d/jellyfin-cleanup && chmod 644 /etc/cron.d/jellyfin-cleanup\"'"
  }
}

# ----------------------------------------------------------------------
# ZFS DISK ALERT — Telegram notification when pool usage >= 80%
# ----------------------------------------------------------------------

resource "null_resource" "deploy_zfs_disk_check_script" {
  triggers = {
    script_version = "v1-daily-top5"
  }

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no scripts/check-zfs-disk.sh root@${local.host_ip}:/usr/local/bin/check-zfs-disk.sh && ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'chmod +x /usr/local/bin/check-zfs-disk.sh'"
  }
}

resource "null_resource" "zfs_disk_check_cron" {
  triggers = {
    cron_spec = "zfs disk check daily at 09:00 threshold 80%"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'sh -c \"echo \\\"0 9 * * * root /usr/local/bin/check-zfs-disk.sh -t 80\\\" > /etc/cron.d/zfs-disk-check && chmod 644 /etc/cron.d/zfs-disk-check\"'"
  }
}

# Manual trigger
resource "null_resource" "zfs_disk_check_manual" {
  triggers = {
    manual_trigger = "run zfs disk check now"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} '/usr/local/bin/check-zfs-disk.sh -t 80'"
  }
}

# ----------------------------------------------------------------------
# MANUAL TRIGGERS — Run cleanup on demand via terraform apply -replace
# ----------------------------------------------------------------------

resource "null_resource" "backup_cleanup_manual" {
  triggers = {
    manual_trigger = "run backup cleanup now"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} '/usr/local/bin/cleanup-backups.sh'"
  }
}

resource "null_resource" "torrent_cleanup_manual" {
  triggers = {
    manual_trigger = "run torrent cleanup now"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 101 -- /usr/local/bin/cleanup-torrents.sh'"
  }
}

resource "null_resource" "soulseek_cleanup_manual" {
  triggers = {
    manual_trigger = "run soulseek cleanup now"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 101 -- /usr/local/bin/cleanup-soulseek.sh'"
  }
}

resource "null_resource" "jellyfin_cleanup_manual" {
  triggers = {
    manual_trigger = "run jellyfin cleanup now"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 105 -- /usr/local/bin/cleanup-jellyfin.sh'"
  }
}