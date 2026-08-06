variable "proxmox_api_token" {
  description = "API Token for Proxmox (format: user@pam!token-id=value)"
  type        = string
  sensitive   = true
}

# Staging flags for the subnet migration (192.168.1.0/24 -> 10.10.10.0/24).
# Shipped false so the refactor PR is diff-neutral; Apply A (task 4.1) flips
# stage_dual_stack=true, and the cutover commits flip the rest:
#   - stage_dual_stack:  host gets 10.10.10.134 alongside 192.168.1.134; docker LXC gets eth1 10.10.10.142
#   - stage_docker_hold: docker net0 stays on the legacy subnet until the final cutover (Apply C)
#   - keep_legacy_host_ip: remove the legacy 192.168.1.134 host IP in the final cleanup
variable "stage_dual_stack" {
  description = "Stage dual-stack: add 10.10.10 addresses before the cutover (true only during Apply A..C window)"
  type        = bool
  default     = false
}

variable "stage_docker_hold" {
  description = "Hold docker LXC 101 net0 on the legacy subnet until the final cutover (Apply C)"
  type        = bool
  default     = true
}

variable "keep_legacy_host_ip" {
  description = "Keep the legacy 192.168.1.134 host IP during and after cutover (set false in final cleanup)"
  type        = bool
  default     = true
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
