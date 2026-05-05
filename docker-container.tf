resource "proxmox_virtual_environment_container" "docker" {
  node_name    = "prxhp136"
  vm_id        = 101
  started      = true
  unprivileged = false

  description = <<-EOT
        <div align='center'>
          <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
            <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
          </a>

          <h2 style='font-size: 24px; margin: 20px 0;'>Debian LXC</h2>

          <p style='margin: 16px 0;'>
            <a href='https://community-scripts.org/donate' target='_blank' rel='noopener noreferrer'>
              <img src='https://img.shields.io/badge/❤️-Sponsoring%20%26%20Donations-FF5E5B' alt='Sponsoring and donations' />
            </a>
          </p>

          <p style='margin: 12px 0;'>
            <a href='https://community-scripts.org/scripts/debian' target='_blank' rel='noopener noreferrer'>
              <img src='https://img.shields.io/badge/📦-Open%20Script%20Page-00617f' alt='Open script page' />
            </a>
          </p>

          <span style='margin: 0 10px;'>
            <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
            <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
          </span>
          <span style='margin: 0 10px;'>
            <i class="fa fa-comments fa-fw" style="color: #f5f5f5;"></i>
            <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
          </span>
          <span style='margin: 0 10px;'>
            <i class="fa fa-exclamation-circle fa-fw" style="color: #f5f5f5;"></i>
            <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
          </span>
        </div>
  EOT

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
    dedicated = 4096
    swap      = 512
  }

  disk {
    datastore_id = "local-zfs"
    size         = 32
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "BC:24:11:C5:96:4D"
    firewall    = true
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
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
      description,
      unprivileged,
      vm_id,
    ]
  }
}
