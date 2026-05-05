variable "proxmox_api_token" {
  description = "API Token for Proxmox (format: user@pam!token-id=value)"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://192.168.1.134:8006/api2/json"
}

variable "local_network" {
  description = "Local network CIDR"
  type        = string
  default     = "192.168.1.0/24"
}

variable "management_ips" {
  description = "IPs allowed for SSH and Proxmox UI (for future tightening)"
  type        = list(string)
  default     = ["192.168.1.0/24"]
}

variable "proxmox_host_ip" {
  description = "Proxmox host IP"
  type        = string
  default     = "192.168.1.134"
}

variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "prxhp136"
}

variable "home_assistant_vm_id" {
  description = "Home Assistant VM ID"
  type        = number
  default     = 100
}
