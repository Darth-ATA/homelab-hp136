# Note: If "changing feature flags is only allowed for root@pam" error occurs:
# Option 1: Remove features block (if present)
# Option 2: Import existing container with: terraform import proxmox_virtual_environment_container.vaultwarden prxhp136/104
resource "proxmox_virtual_environment_container" "vaultwarden" {
  node_name    = "prxhp136"
  vm_id        = 104
  started      = true
  unprivileged = true

  description = "Vaultwarden password manager (Alpine, 1 core, 512MB RAM, 4GB disk)"

  tags = ["community-script", "password-manager", "vaultwarden"]

  initialization {
    hostname = "alpine-vaultwarden"
    ip_config {
      ipv4 {
        address = "192.168.1.144/24"
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
    size         = 4
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "BC:24:11:78:83:C3"
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
    template_file_id = "local:vztmpl/alpine-3.23-default_20260116_amd64.tar.xz"
    type             = "alpine"
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
