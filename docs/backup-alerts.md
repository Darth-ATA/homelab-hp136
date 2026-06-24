# Backup Alerts Setup

Telegram-based backup monitoring for the Proxmox homelab. Two scripts:
- `check-backup-status.sh` — Parses PVE task logs for backup failures, alerts via Telegram.
- `check-backup-disk.sh` — Monitors backup storage disk usage, alerts via Telegram + email.

## Prerequisites

- Telegram bot token and chat ID (already configured for other monitors)
- SSH access to Proxmox host (`192.168.1.134`)
- Terraform applied with `mailnotification = "failure"` on all backup jobs

## Setup

### 1. Create `/root/.env` on Proxmox host

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134
cat > /root/.env << 'EOF'
# Telegram bot credentials — sourced by backup alert scripts
TELEGRAM_BOT_TOKEN="<your-telegram-bot-token>"
TELEGRAM_CHAT_ID="<your-telegram-chat-id>"
EOF
chmod 600 /root/.env
```

Verify the file is sourceable:
```bash
source /root/.env && echo "$TELEGRAM_CHAT_ID"
# Expected output: <your-telegram-chat-id>
```

### 2. Deploy Scripts

From your workstation:
```bash
scp -i ~/.ssh/homelab_key scripts/check-backup-status.sh root@192.168.1.134:/usr/local/bin/
scp -i ~/.ssh/homelab_key scripts/check-backup-disk.sh root@192.168.1.134:/usr/local/bin/
```

On the Proxmox host:
```bash
chmod +x /usr/local/bin/check-backup-status.sh
chmod +x /usr/local/bin/check-backup-disk.sh
```

### 3. Add Cron Entries

Create `/etc/cron.d/backup-alerts`:
```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134
cat > /etc/cron.d/backup-alerts << 'EOF'
# Backup status check — runs after backup window ends (last backup at 04:30)
30 5 * * * root /usr/local/bin/check-backup-status.sh

# Backup disk usage check — every 60 minutes
*/60 * * * * root /usr/local/bin/check-backup-disk.sh -w 80 -c 90
EOF
chmod 644 /etc/cron.d/backup-alerts
```

Verify cron syntax:
```bash
run-parts --test /etc/cron.d
```

If the existing `check-backup-disk` cron line was defined elsewhere (e.g., a separate file), remove the old line to avoid duplicate execution:
```bash
# Check for existing cron entries
grep -r "check-backup-disk" /etc/cron* /var/spool/cron/crontabs/
```

## Manual Verification

### Test backup status check
```bash
/usr/local/bin/check-backup-status.sh
echo "Exit code: $?"
```

Expected outputs:
- **Exit 0**: All backups OK in the last 24h — log shows "All 6 backups completed successfully"
- **Exit 1**: Backups failed — Telegram alert sent, log shows failure details
- **No `/root/.env`**: Script runs, logs warning, no Telegram sent (graceful degradation)

Check logs:
```bash
cat /var/log/check-backup-status.log
```

### Test disk usage check
```bash
# Test with thresholds that will trigger (set artificially low)
/usr/local/bin/check-backup-disk.sh -w 1 -c 2
echo "Exit code: $?"

# Test with realistic thresholds
/usr/local/bin/check-backup-disk.sh -w 80 -c 90
echo "Exit code: $?"
```

Expected outputs:
- **Exit 0**: Usage below warning threshold
- **Exit 1**: Usage at or above warning threshold (check email + Telegram)
- **Exit 2**: Usage at or above critical threshold (check email + Telegram)

Check logs:
```bash
cat /var/log/check-backup-disk.log
```

### Test Telegram integration
```bash
# Temporarily set low thresholds
/usr/local/bin/check-backup-disk.sh -w 1 -c 2
```

You should receive a Telegram warning message in your configured chat within seconds.

Check state tracking:
```bash
cat /var/tmp/check-backup-disk.state
# Expected: PREVIOUS_STATE="warning" and a timestamp
```

## Cron Schedule

| Script | Schedule | Purpose |
|--------|----------|---------|
| `check-backup-status.sh` | `30 5 * * *` | 05:30 daily — 1h after last backup (jellyfin at 04:30) |
| `check-backup-disk.sh` | `*/60 * * * *` | Every 60 min — matches existing schedule |

## Log Files

| File | Script | Retention |
|------|--------|-----------|
| `/var/log/check-backup-status.log` | Status monitor | Managed by logrotate or manual cleanup |
| `/var/log/check-backup-disk.log` | Disk monitor | Managed by logrotate or manual cleanup |
| `/var/tmp/check-backup-status.state` | Status state tracking | Auto-managed (overwritten on each run) |
| `/var/tmp/check-backup-disk.state` | Disk state tracking | Auto-managed (overwritten on each run) |

## State Tracking

Both scripts use a state file to prevent alert spam:
- **Cooldown**: 30 minutes between repeated alerts in the same state
- **State transitions**: Recovery alert sent when transitioning from unhealthy back to healthy
- **File location**: `/var/tmp/check-backup-{status,disk}.state`

## Rollback

### Remove scripts and cron:
```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134
rm /usr/local/bin/check-backup-status.sh
rm /usr/local/bin/check-backup-disk.sh
rm /etc/cron.d/backup-alerts
rm /root/.env
```

### Revert Terraform changes:
```bash
cd /path/to/homelab-terraform
git checkout backup.tf
terraform apply
```

Or manually revert:
```bash
terraform apply -replace=proxmox_backup_job.home_assistant \
                       -replace=proxmox_backup_job.tailscale \
                       -replace=proxmox_backup_job.adguard \
                       -replace=proxmox_backup_job.vaultwarden \
                       -replace=proxmox_backup_job.jellyfin
```

Note: Reverting `mailnotification` from `"failure"` to unset will reset to the Proxmox default of `"always"` (email on every backup).

## Troubleshooting

### No Telegram alerts received
1. Check `/root/.env` exists and has correct tokens:
   ```bash
   source /root/.env && echo "Bot: ${TELEGRAM_BOT_TOKEN:0:8}..., Chat: $TELEGRAM_CHAT_ID"
   ```
2. Verify the bot can send messages:
   ```bash
   curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
   ```
3. Check state file cooldown:
   ```bash
   cat /var/tmp/check-backup-status.state
   ```

### Script fails with "Missing required commands"
Install missing packages:
```bash
apt update && apt install -y bsd-mailx curl
```

### Disk check shows wrong values
Verify the backup storage path:
```bash
df -h /var/lib/vz/dump
ls -la /var/lib/vz/dump
```
