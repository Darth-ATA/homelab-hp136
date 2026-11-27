#!/bin/bash
set -euo pipefail

# Bluetooth USB passthrough healthcheck for Home Assistant VM (100)
# Re-attaches the Realtek RTL8821C (0bda:c821) to the VM when it drops out of
# the USB passthrough config, and reboots the VM as last resort.
#
# Runs on the Proxmox host via cron. Deployed by Terraform (monitoring.tf).

VM_ID=100
BT_SPEC="0bda:c821"
BT_USB_INDEX="usb1"
LOG_FILE="/var/log/bluetooth-healthcheck.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Is the VM running?
vm_status() {
  qm status "$VM_ID" 2>/dev/null | awk '{print $2}'
}

# Is the BT USB spec present in the VM config?
bt_assigned() {
  qm config "$VM_ID" 2>/dev/null | grep -qE "usb[0-9]+: host=$BT_SPEC"
}

# Re-attach the BT USB to the VM. Tries hot-plug first; if the VM is running
# and qemu rejects it, stops the VM, re-attaches, and starts it again.
reattach_bt() {
  log "BT USB $BT_SPEC NOT assigned to VM $VM_ID. Attempting re-attach..."

  if qm set "$VM_ID" -"$BT_USB_INDEX" host="$BT_SPEC" >/dev/null 2>&1; then
    log "Re-attached BT USB $BT_SPEC to VM $VM_ID (hot-plug)"
    return 0
  fi

  log "Hot-plug failed. Stopping VM $VM_ID to re-attach USB..."
  qm stop "$VM_ID" >/dev/null 2>&1 || true

  if qm set "$VM_ID" -"$BT_USB_INDEX" host="$BT_SPEC" >/dev/null 2>&1; then
    log "Re-attached BT USB $BT_SPEC to VM $VM_ID (VM stopped)"
    qm start "$VM_ID" >/dev/null 2>&1 && log "VM $VM_ID started" || log "Failed to start VM $VM_ID"
    return 0
  fi

  log "Failed to re-attach BT USB $BT_SPEC to VM $VM_ID"
  return 1
}

main() {
  if ! bt_assigned; then
    reattach_bt || true
    return
  fi

  local status
  status="$(vm_status)"
  if [ "$status" != "running" ]; then
    log "BT USB assigned but VM $VM_ID is not running ($status). Skipping."
    return
  fi

  log "BT USB $BT_SPEC assigned to VM $VM_ID and VM is running."
}

main
