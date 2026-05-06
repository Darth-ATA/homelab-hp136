# Home Assistant VM (HAOS)
resource "proxmox_virtual_environment_vm" "home_assistant" {
  node_name = var.proxmox_node_name
  vm_id     = var.home_assistant_vm_id

  name        = "haos-17.1"
  description = "Home Assistant OS 17.1"
  tags        = ["community-script"]
  started     = true
  template    = false
  machine     = "q35"
  bios        = "ovmf"
  scsi_hardware = "virtio-scsi-pci"
  tablet_device = false
  protection  = false

  agent {
    enabled = true
    timeout = "15m"
    trim    = false
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "qemu64"
    units   = 1024
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-zfs"
    file_format  = "raw"
    interface    = "scsi0"
    size         = 32
    cache        = "none"
    discard      = "on"
    aio          = "io_uring"
    ssd          = true
    backup       = true
    replicate    = true
  }

  efi_disk {
    datastore_id = "local-zfs"
    file_format  = "raw"
    type         = "4m"
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = false
  }

  operating_system {
    type = "l26"
  }

  serial_device {
    device = "socket"
  }

  # USB passthrough (Zigbee/Z-Wave stick: 10c4:ea60)
  usb {
    host = "10c4:ea60"
  }
}

# Firewall Options for Home Assistant VM
resource "proxmox_virtual_environment_firewall_options" "home_assistant" {
  node_name = var.proxmox_node_name
  vm_id     = var.home_assistant_vm_id

  enabled       = true
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
  ipfilter      = true
}
