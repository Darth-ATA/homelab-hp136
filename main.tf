terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.76.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

data "proxmox_virtual_environment_nodes" "available" {}

output "node_info" {
  value = data.proxmox_virtual_environment_nodes.available.names
}
