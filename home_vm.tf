# Home Assistant VM (HAOS)
resource "proxmox_virtual_environment_vm" "home_assistant" {
  node_name = var.proxmox_node_name
  vm_id     = var.home_assistant_vm_id

  name          = "haos-17.1"
  description   = "Home Assistant OS 17.1"
  tags          = ["community-script"]
  started       = true
  template      = false
  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-pci"
  tablet_device = false
  protection    = false

  agent {
    enabled = true
    timeout = "15m"
    trim    = false
    type    = "virtio"
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

  usb {
    host = "10c4:ea60"
    usb3 = false
  }

  usb {
    host = "0bda:c821"
    usb3 = false
  }

  lifecycle {
    ignore_changes = [
      usb,
    ]
  }
}

# USB passthrough for built-in Bluetooth (Realtek RTL8821C 0bda:c821)
# NOTE: Set via SSH because API token can't pass real USB devices (root-only)
resource "null_resource" "bluetooth_usb_passthrough" {
  triggers = {
    vm_id       = var.home_assistant_vm_id
    bt_usb_spec = "0bda:c821"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'qm set ${var.home_assistant_vm_id} -usb1 host=0bda:c821 >/dev/null 2>&1'"
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
