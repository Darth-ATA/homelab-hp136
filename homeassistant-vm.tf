# Home Assistant VM (HAOS) Firewall Configuration
# VM 100 is manually created and NOT managed by Terraform
# (See README.md for explanation regarding provider bugs)

# Firewall Options for Home Assistant VM
resource "proxmox_virtual_environment_firewall_options" "homeassistant" {
  node_name = "prxhp136"
  vm_id     = 100

  enabled       = true
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
  ipfilter      = true
}
