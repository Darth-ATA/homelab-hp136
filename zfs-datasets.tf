# ZFS Dataset Tuning
# Manages ZFS dataset properties that are not exposed via the Proxmox API.
# Uses null_resource + local-exec to apply settings via SSH on the Proxmox host.

locals {
  # Media dataset — shared bind mount between LXC 101 (docker) and LXC 105 (jellyfin)
  # Stores videos, torrents, and other large media files
  media_dataset            = "rpool/data/media"
  media_dataset_recordsize = "1M"
  media_dataset_atime      = "off"

  # Torrents dataset — Deluge downloads on dedicated ZFS dataset
  torrents_dataset            = "rpool/data/torrents"
  torrents_dataset_recordsize = "1M"
  torrents_dataset_atime      = "off"

  # Soulseek dataset — slskd downloads on dedicated ZFS dataset
  soulseek_dataset            = "rpool/data/soulseek"
  soulseek_dataset_recordsize = "1M"
  soulseek_dataset_atime      = "off"
}

# Apply ZFS tuning for the media dataset
# recordsize=1M: Large files (videos, torrents) benefit from 1M block size — less fragmentation,
#   better compression ratios, and improved sequential read throughput.
# atime=off: No need to track file access times on media storage — saves writes and metadata overhead.
resource "null_resource" "zfs_dataset_media_tuning" {
  triggers = {
    dataset    = local.media_dataset
    recordsize = local.media_dataset_recordsize
    atime      = local.media_dataset_atime
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'zfs set recordsize=${local.media_dataset_recordsize} ${local.media_dataset} && zfs set atime=${local.media_dataset_atime} ${local.media_dataset}'"
  }
}

# Apply ZFS tuning for the torrents dataset
# recordsize=1M: Large files (videos, torrents) benefit from 1M block size
# atime=off: No need to track file access times on torrent storage
resource "null_resource" "zfs_dataset_torrents_tuning" {
  triggers = {
    dataset    = local.torrents_dataset
    recordsize = local.torrents_dataset_recordsize
    atime      = local.torrents_dataset_atime
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'zfs set recordsize=${local.torrents_dataset_recordsize} ${local.torrents_dataset} && zfs set atime=${local.torrents_dataset_atime} ${local.torrents_dataset}'"
  }
}

# Apply ZFS tuning for the soulseek dataset
# recordsize=1M: Large files (videos, torrents) benefit from 1M block size
# atime=off: No need to track file access times on soulseek storage
resource "null_resource" "zfs_dataset_soulseek_tuning" {
  triggers = {
    dataset    = local.soulseek_dataset
    recordsize = local.soulseek_dataset_recordsize
    atime      = local.soulseek_dataset_atime
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'zfs set recordsize=${local.soulseek_dataset_recordsize} ${local.soulseek_dataset} && zfs set atime=${local.soulseek_dataset_atime} ${local.soulseek_dataset}'"
  }
}
