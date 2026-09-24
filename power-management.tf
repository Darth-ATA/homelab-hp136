# ============================================================
# POWER MANAGEMENT — Scheduled shutdown/startup with Frigate exception
# ============================================================
# Pattern: Deploy scripts from scripts/power/ then install cron/systemd via null_resource
# All operations run on Proxmox host via SSH
# ============================================================

locals {
  shutdown_script_hash   = filebase64sha256("${path.module}/scripts/power/homelab-shutdown.sh")
  suspend_script_hash    = filebase64sha256("${path.module}/scripts/power/homelab-suspend.sh")
  wake_service_hash      = filebase64sha256("${path.module}/scripts/power/homelab-wake.service")
  wake_timer_hash        = filebase64sha256("${path.module}/scripts/power/homelab-wake.timer")
  wake_alarm_script_hash = filebase64sha256("${path.module}/scripts/power/homelab-set-wake-alarm.sh")
  wol_link_hash          = filebase64sha256("${path.module}/scripts/power/99-wol.link")
}

# ─── Script Deployment ──────────────────────────────────────────────────────────

resource "null_resource" "deploy_shutdown_script" {
  triggers = {
    script_hash = local.shutdown_script_hash
  }

provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/power/homelab-shutdown.sh root@${var.proxmox_host_ip}:/usr/local/bin/homelab-shutdown.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/homelab-shutdown.sh'
EOT
  }
}

resource "null_resource" "deploy_wake_alarm_script" {
  triggers = {
    script_hash = local.wake_alarm_script_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/power/homelab-set-wake-alarm.sh root@${var.proxmox_host_ip}:/usr/local/bin/homelab-set-wake-alarm.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/homelab-set-wake-alarm.sh'
EOT
  }
}

resource "null_resource" "deploy_wake_service" {
  triggers = {
    service_hash = local.wake_service_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/power/homelab-wake.service root@${var.proxmox_host_ip}:/etc/systemd/system/homelab-wake.service && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'systemctl daemon-reload'
EOT
  }
}

resource "null_resource" "deploy_wake_timer" {
  triggers = {
    timer_hash = local.wake_timer_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/power/homelab-wake.timer root@${var.proxmox_host_ip}:/etc/systemd/system/homelab-wake.timer && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'systemctl daemon-reload'
EOT
  }
}

resource "null_resource" "deploy_wol_link" {
  triggers = {
    link_hash = local.wol_link_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/power/99-wol.link root@${var.proxmox_host_ip}:/etc/systemd/network/99-wol.link && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'systemctl restart systemd-udevd'
EOT
  }
}

resource "null_resource" "deploy_suspend_script" {
  triggers = {
    script_hash = local.suspend_script_hash
  }

  provisioner "local-exec" {
    command = <<EOT
scp -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no ${path.module}/scripts/power/homelab-suspend.sh root@${var.proxmox_host_ip}:/usr/local/bin/homelab-suspend.sh && \
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'chmod 755 /usr/local/bin/homelab-suspend.sh'
EOT
  }
}

# ─── Cron Job: Daily Shutdown at 03:00 UTC (00:00 ARG) ──────────────────────────

resource "null_resource" "shutdown_cron" {
  triggers = {
    cron_spec = "daily shutdown at 03:00 UTC (00:00 ARG) with Frigate check"
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
cat > /etc/cron.d/homelab-scheduled-shutdown << 'CRONEOF'
# Homelab scheduled shutdown — runs at 03:00 UTC (00:00 Argentina time)
# Checks for Frigate in LXC 101 (Docker) and host systemd before shutting down
0 3 * * * root /usr/local/bin/homelab-shutdown.sh
CRONEOF
chmod 644 /etc/cron.d/homelab-scheduled-shutdown
REMOTE
EOT
  }
}

# ─── Cron Job: Daily Suspend at 00:00 Local (Europe/Madrid) ───────────────────────
# Runs at midnight Spain time (00:00 CET/CEST) — stops fan, wakes at 07:00 local via RTC

resource "null_resource" "suspend_cron" {
  triggers = {
    cron_spec = "daily suspend at 00:00 local (Spain) with Frigate check"
  }

  depends_on = [
    null_resource.deploy_suspend_script,
  ]

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
cat > /etc/cron.d/homelab-scheduled-suspend << 'CRONEOF'
# Homelab scheduled suspend — runs at 00:00 local time (Europe/Madrid)
# Checks for Frigate in LXC 101 (Docker) and host systemd before suspending
# Host wakes automatically via RTC alarm set by homelab-wake.timer (07:00 local = Europe/Madrid)
0 0 * * * root /usr/local/bin/homelab-suspend.sh
CRONEOF
chmod 644 /etc/cron.d/homelab-scheduled-suspend
REMOTE
EOT
  }
}

# ─── Systemd Timer: Enable and Start Wake Timer ─────────────────────────────────

resource "null_resource" "enable_wake_timer" {
  triggers = {
    timer_enable = "enable homelab-wake.timer for daily RTC wake alarm"
  }

  depends_on = [
    null_resource.deploy_wake_timer,
    null_resource.deploy_wake_service,
  ]

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
# Enable and start the timer (persistent across reboots)
systemctl enable --now homelab-wake.timer
# Show status for verification
systemctl status homelab-wake.timer --no-pager
REMOTE
EOT
  }
}

# ─── Manual Trigger: Test Wake Alarm Now ────────────────────────────────────────

resource "null_resource" "test_wake_alarm_manual" {
  triggers = {
    manual_trigger = "test wake alarm calculation now"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} '/usr/local/bin/homelab-set-wake-alarm.sh'"
  }
}

# ─── Manual Trigger: Test Shutdown Script (dry-run, no actual shutdown) ─────────

resource "null_resource" "test_shutdown_script_manual" {
  triggers = {
    manual_trigger = "test shutdown script logic (dry-run)"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} '/usr/local/bin/homelab-shutdown.sh --dry-run 2>&1 || true'"
  }
}

# ─── Manual Trigger: Test Suspend Script (dry-run, no actual suspend) ─────────────

resource "null_resource" "test_suspend_script_manual" {
  triggers = {
    manual_trigger = "test suspend script logic (dry-run)"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} '/usr/local/bin/homelab-suspend.sh --dry-run 2>&1 || true'"
  }
}