terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.76.0"
    }
  }

  backend "s3" {
    bucket                      = "homelab-terraform-state"
    key                         = "terraform.tfstate"
    region                      = "garage"
    endpoints = {
      s3 = "http://192.168.1.142:3900"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
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
