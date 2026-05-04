variable "proxmox_api_token" {
  description = "API Token para Proxmox (formato: user@pam!token-id=value)"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "URL del endpoint de Proxmox"
  type        = string
  default     = "https://192.168.1.134:8006/api2/json"
}
