# Home Assistant VM (HAOS) Firewall Configuration
# VM 100 is manually created and NOT managed by Terraform
# (See README.md for explanation regarding provider bugs)

# Firewall Options for Home Assistant VM
resource "proxmox_virtual_environment_firewall_options" "home_assistant" {
  node_name = var.proxmox_node_name
  vm_id     = var.home_assistant_vm_id

  enabled       = true
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
  ipfilter      = true
}
