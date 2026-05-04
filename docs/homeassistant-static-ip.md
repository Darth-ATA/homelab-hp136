# Home Assistant Static IP Configuration

Home Assistant runs as VM 100 (not LXC), so the IP must be set inside HA OS.

## Method 1: HA OS Web Interface (Recommended)

1. Access Home Assistant at `http://192.168.1.100:8123` (or current IP)
2. Go to **Settings** > **System** > **Network**
3. Click on the network interface (usually `eth0`)
4. Change from DHCP to **Static IP**
5. Enter:
   - **IP Address**: `192.168.1.100`
   - **Subnet mask**: `24` (or `255.255.255.0`)
   - **Gateway**: `192.168.1.1`
   - **DNS Server**: `192.168.1.2` (AdGuard)
6. Click **Save**

## Method 2: HA CLI (if you have console access)

If you have Proxmox console access to VM 100:

```bash
# Login to HA CLI
ha network update eth0 --ipv4-method static --ipv4-address 192.168.1.100/24 --ipv4-gateway 192.168.1.1 --ipv4-dns 192.168.1.2
```

## Verify:

After setting static IP, reboot HA and verify:
```bash
ping 192.168.1.100
```

Then test access via NPM proxy:
```
http://homeassistant.local
```
