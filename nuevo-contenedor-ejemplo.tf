# Ejemplo: Crear un NUEVO contenedor (no afecta los existentes)
resource "proxmox_virtual_environment_container" "nuevo_contenedor" {
  node_name = "prxhp136"
  vm_id     = 200  # ID nuevo, no usado
  started   = true
  
  initialization {
    hostname = "nuevo-contenedor"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
  
  cpu {
    cores = 1
  }
  
  memory {
    dedicated = 512
  }
  
  disk {
    datastore_id = "local-zfs"
    size         = 4
  }
  
  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }
  
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }
}
