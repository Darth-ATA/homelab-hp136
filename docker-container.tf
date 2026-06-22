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
    ]
  }
}
