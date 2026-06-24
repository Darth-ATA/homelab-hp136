# Firewall Configuration
# Enabled with permissive ACCEPT policies to avoid breaking existing services
# See Issue #X for future hardening (restrict to management IPs)

# Enable Cluster Firewall (permissive mode)
resource "proxmox_virtual_environment_cluster_firewall" "cluster" {
  enabled = true

  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"

  log_ratelimit {
    enabled = true
    burst   = 10
    rate    = "5/second"
  }
}

# Security Group: Management Access (SSH + Proxmox UI)
# Note: Currently permissive - restrict source in future hardening issue
resource "proxmox_virtual_environment_cluster_firewall_security_group" "mgmt" {
  name    = "mgmt"
  comment = "Management access - SSH + Proxmox UI (restrict in future issue)"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "SSH (future: restrict to management IPs)"
    dport   = "22"
    proto   = "tcp"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Proxmox UI (future: restrict to management IPs)"
    dport   = "8006"
    proto   = "tcp"
    dest    = var.proxmox_host_ip
  }
}

# Security Group: AdGuard DNS
resource "proxmox_virtual_environment_cluster_firewall_security_group" "dns" {
  name    = "dns"
  comment = "AdGuard DNS access from local network"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "DNS TCP"
    dest    = "192.168.1.2"
    dport   = "53"
    proto   = "tcp"
    source  = var.local_network
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "DNS UDP"
    dest    = "192.168.1.2"
    dport   = "53"
    proto   = "udp"
    source  = var.local_network
  }
}

# Security Group: Web Services (Docker/NPM)
resource "proxmox_virtual_environment_cluster_firewall_security_group" "web" {
  name    = "web"
  comment = "Docker/NPM web services"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "HTTP"
    dest    = "192.168.1.142"
    dport   = "80"
    proto   = "tcp"
    source  = var.local_network
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "HTTPS"
    dest    = "192.168.1.142"
    dport   = "443"
    proto   = "tcp"
    source  = var.local_network
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "NPM Admin"
    dest    = "192.168.1.142"
    dport   = "81"
    proto   = "tcp"
    source  = var.local_network
  }
}

# Security Group: Home Assistant
resource "proxmox_virtual_environment_cluster_firewall_security_group" "home_assistant" {
  name    = "homeassistant"
  comment = "Home Assistant"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Home Assistant UI"
    dest    = "192.168.1.100"
    dport   = "8123"
    proto   = "tcp"
    source  = var.local_network
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "mDNS (Zeroconf discovery)"
    dest    = "192.168.1.100"
    dport   = "5353"
    proto   = "udp"
    source  = var.local_network
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "UPnP (discovery)"
    dest    = "192.168.1.100"
    dport   = "1900"
    proto   = "udp"
    source  = var.local_network
  }
}

# Security Group: Tailscale (optional - UDP 41641 for direct connections)
resource "proxmox_virtual_environment_cluster_firewall_security_group" "tailscale" {
  name    = "tailscale"
  comment = "Tailscale (UDP 41641 for direct connections)"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Tailscale UDP"
    dest    = "192.168.1.102"
    dport   = "41641"
    proto   = "udp"
    source  = var.local_network
  }
}

# Security Group: Vaultwarden
resource "proxmox_virtual_environment_cluster_firewall_security_group" "vaultwarden" {
  name    = "vaultwarden"
  comment = "Vaultwarden HTTP access from local network"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Vaultwarden HTTP"
    dest    = "192.168.1.144"
    dport   = "8000"
    proto   = "tcp"
    source  = var.local_network
  }
}

# Security Group: Jellyfin (LXC 105)
resource "proxmox_virtual_environment_cluster_firewall_security_group" "jellyfin" {
  name    = "jellyfin"
  comment = "Jellyfin media server access from local network"

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Jellyfin HTTP"
    dest    = "192.168.1.145"
    dport   = "8096"
    proto   = "tcp"
    source  = var.local_network
  }
}

# Cluster-Level Firewall Rules (apply security groups)
# NOTE: If "Existing rules detected" error occurs, import existing rules:
# terraform import proxmox_virtual_environment_firewall_rules.cluster cluster
resource "proxmox_virtual_environment_firewall_rules" "cluster" {
  # No node_name/vm_id/container_id = cluster-level

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.mgmt.name
    comment        = "Management access"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.dns.name
    comment        = "AdGuard DNS"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.web.name
    comment        = "Web services (Docker/NPM)"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.home_assistant.name
    comment        = "Home Assistant"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.tailscale.name
    comment        = "Tailscale"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.vaultwarden.name
    comment        = "Vaultwarden"
  }

  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.jellyfin.name
    comment        = "Jellyfin"
  }
}
