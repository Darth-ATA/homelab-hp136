#!/bin/bash
# Run on the Proxmox node via maintenance.tf; guests have their own update policy.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update --error-on=any
apt-get install -y --no-remove --no-install-recommends unattended-upgrades

# APT lists are additive: clear both origin lists before setting the allowlist.
cat > /etc/apt/apt.conf.d/99-homelab-security <<'APT'
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
