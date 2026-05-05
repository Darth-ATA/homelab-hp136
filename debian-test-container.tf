resource "proxmox_virtual_environment_container" "debian_test" {
  node_name    = "prxhp136"
  vm_id        = 105
  started      = true
  unprivileged = false

  initialization {
    hostname = "debian-test"
    ip_config {
      ipv4 {
        address = "192.168.1.105/24"
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
    size         = 8
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "BC:24:11:45:B1:F4"
    firewall    = true
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
    type             = "debian"
  }

  lifecycle {
    ignore_changes = [
      operating_system,
      description,
      unprivileged,
      vm_id,
    ]
  }
}
