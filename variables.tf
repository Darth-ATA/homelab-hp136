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
