# Host-only maintenance; no changes to LXC packages, HAOS or Docker images.
resource "null_resource" "host_security_updates" {
  triggers = {
    host        = local.host_ip
    script_hash = filesha256("${path.module}/scripts/setup-security-updates.sh")
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o BatchMode=yes root@${self.triggers.host} 'bash -s' < '${path.module}/scripts/setup-security-updates.sh'"
  }
}

resource "null_resource" "host_health_check" {
  triggers = {
    host        = local.host_ip
    script_hash = filesha256("${path.module}/scripts/check-host-health.sh")
    cron        = "*/15 * * * * root /usr/local/bin/check-host-health.sh"
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ~/.ssh/homelab_key -o BatchMode=yes root@${self.triggers.host} 'set -e
        install -m 0755 /dev/stdin /usr/local/bin/check-host-health.sh
        printf "%s\n" "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "${self.triggers.cron}" > /etc/cron.d/homelab-health
        chmod 0644 /etc/cron.d/homelab-health' < '${path.module}/scripts/check-host-health.sh'
    EOT
  }
}
