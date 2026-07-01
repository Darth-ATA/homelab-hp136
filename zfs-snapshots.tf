# ZFS Auto-Snapshots
# Installs and configures zfs-auto-snapshot on the Proxmox host to automatically
# snapshot rpool/data/media. Only datasets with com.sun:auto-snapshot=true are
# snapshotted — all parent datasets are explicitly set to false.
# Uses null_resource + local-exec to configure via SSH on the Proxmox host.

resource "null_resource" "zfs_auto_snapshots" {
  triggers = {
    dataset       = "rpool/data/media"
    description   = "ZFS auto-snapshot: daily(7d) + weekly(4w)"
    frequent_keep = 4
    hourly_keep   = 24
    daily_keep    = 7
    weekly_keep   = 4
    monthly_keep  = 12
  }

  provisioner "local-exec" {
    command = <<EOT
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${var.proxmox_host_ip} 'bash -s' << 'REMOTE'
set -e
which zfs-auto-snapshot > /dev/null 2>&1 || apt-get install -y -qq zfs-auto-snapshot
zfs set com.sun:auto-snapshot=true rpool/data/media
zfs set com.sun:auto-snapshot=false rpool
zfs set com.sun:auto-snapshot=false rpool/ROOT
zfs set com.sun:auto-snapshot=false rpool/data
cat > /etc/cron.d/zfs-auto-snapshot << 'CRONEOF'
PATH="/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

*/15 * * * * root which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=frequent --keep=4 //

0 * * * * root which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=hourly --keep=24 //

0 0 * * * root which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=daily --keep=7 //

0 0 * * 0 root which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=weekly --keep=4 //

0 0 1 * * root which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=monthly --keep=12 //
CRONEOF
chmod 644 /etc/cron.d/zfs-auto-snapshot
REMOTE
EOT
  }
}
