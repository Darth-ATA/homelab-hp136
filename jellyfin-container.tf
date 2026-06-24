# Note: Import after community script creates the container:
#   terraform import proxmox_virtual_environment_container.jellyfin prxhp136/105
resource "proxmox_virtual_environment_container" "jellyfin" {
  node_name    = "prxhp136"
  vm_id        = 105
  started      = true
  unprivileged = true

  description = "Jellyfin media server (Ubuntu 24.04, 2 cores, 4GB RAM, 16GB disk, iGPU passthrough)"

  tags = ["community-script", "media", "jellyfin"]

  initialization {
    hostname = "jellyfin"
    ip_config {
      ipv4 {
        address = "192.168.1.145/24"
        gateway = "192.168.1.1"
      }
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
    swap      = 512
  }

  disk {
    datastore_id = "local-zfs"
    size         = 16
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "BC:24:11:46:95:DE"
    firewall    = true
  }

  features {
    fuse    = false
    keyctl  = true
    mknod   = false
    mount   = []
    nesting = true
  }

  operating_system {
    template_file_id = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    type             = "ubuntu"
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  device_passthrough {
    path       = "/dev/dri/renderD128"
    uid        = 0
    gid        = 993
    mode       = "0666"
    deny_write = false
  }

  device_passthrough {
    path       = "/dev/dri/card0"
    uid        = 0
    gid        = 44
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
      device_passthrough,
    ]
  }
}

# ZFS dataset for media (shared between LXC 101 and LXC 105)
# NOTE: Created once via `zfs create rpool/data/media` on Proxmox host
# Terraform does not manage the dataset lifecycle directly.
# Mount points are added via null_resource + local-exec.

# Mount point: LXC 105 media bind mount
resource "null_resource" "jellyfin_mount_point" {
  depends_on = [proxmox_virtual_environment_container.jellyfin]

  triggers = {
    container_id = 105
    mount_spec   = "/rpool/data/media,mp=/media"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'pct set 105 -mp0 /rpool/data/media,mp=/media 2>/dev/null; pct exec 105 -- mkdir -p /media'"
  }
}
