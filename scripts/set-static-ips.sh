#!/bin/bash
# Set static IPs for Proxmox LXC containers
# Run this on the Proxmox host (192.168.1.134) as root

set -e

echo "Setting static IPs for LXC containers..."

# Container configurations: ID|IP|Gateway
containers=(
    "101|192.168.1.142|Home Assistant (Docker/NPM)"
    "102|192.168.1.102|Tailscale"
    "103|192.168.1.2|AdGuard Home"
    "105|192.168.1.105|Debian Test"
)

for container in "${containers[@]}"; do
    IFS='|' read -r id ip desc <<< "$container"

    config_file="/etc/pve/lxc/${id}.conf"

    if [[ ! -f "$config_file" ]]; then
        echo "WARNING: Config file $config_file not found, skipping $desc (ID: $id)"
        continue
    fi

    echo "Processing $desc (ID: $id) - Setting IP: $ip"

    # Remove existing DHCP network config
    sed -i '/^net0:/d' "$config_file"

    # Add static IP configuration
    echo "net0: name=eth0,bridge=vmbr0,firewall=1,ip=${ip}/24,gateway=192.168.1.1,type=veth" >> "$config_file"

    echo "  Updated $config_file"
done

echo ""
echo "Static IPs configured. Restarting containers to apply changes..."
echo "Run: pct stop <ID> && pct start <ID> for each container"
echo ""
echo "Container summary:"
printf "  %-4s | %-18s | %s\n" "ID" "IP Address" "Description"
printf "  %-4s | %-18s | %s\n" "----" "------------------" "-----------"
for container in "${containers[@]}"; do
    IFS='|' read -r id ip desc <<< "$container"
    printf "  %-4s | %-18s | %s\n" "$id" "$ip" "$desc"
done

echo ""
echo "Next steps:"
echo "1. Restart each container: for id in 101 102 103 105; do pct stop \$id && pct start \$id; done"
echo "2. Configure Home Assistant VM (ID 100) with static IP 192.168.1.100 inside HA OS"
echo "3. Configure AdGuard DNS records (see adguard-dns-records.md)"
echo "4. Configure Nginx Proxy Manager (see npm-config.md)"
