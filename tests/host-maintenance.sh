#!/bin/bash
# Offline smoke tests; all PVE and journal commands are local test doubles.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PATH="$tmp:$PATH" CALLS="$tmp/calls"
cat > "$tmp/pvesm" <<'MOCK'
#!/bin/sh
echo "$*" >> "$CALLS"
MOCK
cat > "$tmp/df" <<'MOCK'
#!/bin/sh
printf 'mock fs\nfs 100 80 20 %s%% /\n' "${DISK:-79}"
MOCK
cat > "$tmp/systemctl" <<'MOCK'
#!/bin/sh
[ "$*" != "is-active --quiet ${DOWN:-none}" ]
MOCK
cat > "$tmp/pct" <<'MOCK'
#!/bin/sh
if [ "$2" = "${STOPPED:-none}" ]; then echo 'status: stopped'; else echo 'status: running'; fi
MOCK
ln -s pct "$tmp/qm"
cat > "$tmp/logger" <<'MOCK'
#!/bin/sh
echo "$*" >> "$CALLS"
MOCK
# Supply deterministic CPU and RAM samples to the actual awk code.
cat > "$tmp/awk" <<'MOCK'
#!/bin/sh
case "$2" in
    /proc/stat)
        idle=100; user=50
        if [ -f "$CALLS.cpu" ]; then idle=$((idle+100-${BUSY:-0})); user=$((user+${BUSY:-0})); fi
        touch "$CALLS.cpu"
        printf 'cpu %d 0 50 %d 0 0 0 0 0 0\n' "$user" "$idle" | /usr/bin/awk "$1" ;;
    /proc/meminfo)
        printf 'MemTotal: 100 kB\nMemAvailable: %d kB\n' "${AVAILABLE:-40}" | /usr/bin/awk "$1" ;;
    *) exec /usr/bin/awk "$@" ;;
esac
MOCK
chmod +x "$tmp"/{awk,df,logger,pct,pvesm,systemctl}

bash scripts/cleanup-backups.sh --dry-run >/dev/null
for id in 100 101 102 103 104 105; do
    type=lxc; [[ $id != 100 ]] || type=qemu
    grep -Fxq "prune-backups local --type $type --vmid $id --keep-daily 7 --keep-monthly 6 --dry-run 1" "$CALLS"
done
if bash scripts/cleanup-backups.sh --invalid 2>/dev/null; then exit 1; fi
[[ $(wc -l < "$CALLS") -eq 6 ]]

bash scripts/check-host-health.sh
rm "$CALLS.cpu"
if BUSY=90 DISK=80 AVAILABLE=10 DOWN=pveproxy STOPPED=105 bash scripts/check-host-health.sh 2>"$tmp/warnings"; then exit 1; fi
for expected in 'CPU busy: 90%' 'RAM used: 90%' 'Filesystem /var/lib/vz used: 80%' 'Service pveproxy inactive' 'pct guest 105: status: stopped'; do
    grep -Fq "$expected" "$CALLS"
done
echo 'Host maintenance smoke tests passed.'
