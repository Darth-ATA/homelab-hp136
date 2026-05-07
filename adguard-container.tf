# Note: If "changing feature flags is only allowed for root@pam" error occurs:
# Option 1: Remove features block (if present)
# Option 2: Import existing container with: terraform import proxmox_virtual_environment_container.adguard prxhp136/103
resource "proxmox_virtual_environment_container" "adguard" {
  node_name    = "prxhp136"
  vm_id        = 103
  started      = true
  unprivileged = false

  description = "AdGuard Home DNS ad-blocker (1 core, 512MB RAM, 2GB disk)"

  tags = ["adblock", "community-script"]

  initialization {
    hostname = "adguard"
    ip_config {
      ipv4 {
        address = "192.168.1.2/24"
        gateway = "192.168.1.1"
      }
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 512
  }

  disk {
    datastore_id = "local-zfs"
    size         = 2
  }

   network_interface {
     name        = "eth0"
     bridge      = "vmbr0"
     mac_address = "BC:24:11:D5:A2:77"
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
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  lifecycle {
    ignore_changes = [
      operating_system,
      unprivileged,
      vm_id,
    ]
  }
}
