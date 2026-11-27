#!/bin/bash
# Read-only checks for the PVE node. Silent on success; warnings go to the journal.
set -uo pipefail
export LC_ALL=C
failed=0
warn() {
    printf '%s\n' "$*" >&2
    logger -p daemon.warning -t homelab-health -- "$*"
    failed=1
}

# Report busy CPU across all cores (exclude idle/iowait; guest ticks are already
# included in user/nice). Two samples avoid reporting a since-boot average.
cpu_ticks() {
    awk '/^cpu / {for (i=2; i<=9; i++) total+=$i; printf "%.0f %.0f\n", total, $5+$6; exit}' /proc/stat
}
if read -r total idle < <(cpu_ticks) && sleep 1 && read -r end free < <(cpu_ticks) && ((end > total)); then
    cpu=$((100 * (end-total-free+idle) / (end-total)))
    ((cpu < 90)) || warn "CPU busy: ${cpu}%"
else
    warn 'Cannot sample CPU usage'
fi

if ram=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if (!t || a=="") exit 1; print int(100*(t-a)/t)}' /proc/meminfo); then
    ((ram < 90)) || warn "RAM used: ${ram}%"
else
    warn 'Cannot read available memory'
fi

for path in / /var/lib/vz; do
    if disk=$(df -P "$path" | awk 'NR==2 {gsub(/%/, "", $5); print $5}') && [[ $disk =~ ^[0-9]+$ ]]; then
        ((disk < 80)) || warn "Filesystem $path used: ${disk}%"
    else
        warn "Cannot measure filesystem $path"
    fi
done

for unit in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    timeout 10 systemctl is-active --quiet "$unit" || warn "Service $unit inactive or unavailable"
done

for id in 100 101 102 103 104 105; do
    tool=pct
    [[ $id != 100 ]] || tool=qm
    if ! status=$(timeout 15 "$tool" status "$id") || [[ $status != 'status: running' ]]; then
        warn "$tool guest $id: ${status:-status unavailable}"
    fi
done
exit "$failed"
