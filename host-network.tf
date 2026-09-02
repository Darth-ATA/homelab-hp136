# Host dual-stack: add the NEW subnet IP (10.10.10.134) to vmbr0 BEFORE the
# cutover (design D5). The Proxmox host is not Terraform-managed, so this
# follows the project null_resource + local-exec pattern (see usb passthrough,
# zfs tuning). Idempotent: only adds the address if not already present, both
# in the persistent /etc/network/interfaces and at runtime.
#
# The old IP (192.168.1.134) is kept until the final cleanup step, gated by
# var.keep_legacy_host_ip (task 6.2).

resource "null_resource" "host_dual_stack" {
  count = var.stage_dual_stack ? 1 : 0

  triggers = {
    host_ip = local.host_ip
    new_ip  = "${local.new_subnet_base}.${local.node_ips.host}"
    cidr    = "/24"
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'bash -s' << 'REMOTE'
set -e
NEW_IP="${local.new_subnet_base}.${local.node_ips.host}"
# Persistent: add to /etc/network/interfaces under the vmbr0 stanza (idempotent)
if ! grep -q "address $${NEW_IP}" /etc/network/interfaces; then
  sed -i "s|address ${local.host_ip}/24|&\n\taddress $${NEW_IP}/24|" /etc/network/interfaces
fi
# Runtime: add immediately without reboot (idempotent)
if ! ip -4 addr show vmbr0 | grep -q "$${NEW_IP}"; then
  ip addr add $${NEW_IP}/24 dev vmbr0
fi
ip -4 addr show vmbr0 | grep inet
REMOTE
EOT
  }
}
