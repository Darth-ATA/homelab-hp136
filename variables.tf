variable "proxmox_api_token" {
  description = "API Token for Proxmox (format: user@pam!token-id=value)"
  type        = string
  sensitive   = true
}

variable "proxmox_host_ip" {
  description = "Proxmox host IP (legacy variable, being phased out)"
  type        = string
  default     = "10.10.10.134"
}

# Migration complete: all staging flags set to false (final state)
variable "stage_dual_stack" {
  description = "Stage dual-stack: add 10.10.10 addresses before the cutover (false after migration complete)"
  type        = bool
  default     = false
}

variable "stage_docker_hold" {
  description = "Hold docker LXC 101 net0 on the legacy subnet until the final cutover (false after migration complete)"
  type        = bool
  default     = false
}

variable "keep_legacy_host_ip" {
  description = "Keep the legacy 192.168.1.134 host IP during and after cutover (false after migration complete)"
  type        = bool
  default     = false
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
