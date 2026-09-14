# AdGuard Home DNS Records

Access AdGuard at: http://10.10.10.2

## Steps to Add DNS Records:

1. Login to AdGuard Admin panel
2. Go to **Filters > DNS rewrites**
3. Click **Add DNS rewrite**

## DNS Records to Add:

| Domain | IP Address | Description |
|--------|------------|-------------|
| `homeassistant.local` | `10.10.10.142` | Home Assistant (proxied via NPM) |
| `adguard.local` | `10.10.10.2` | AdGuard Home admin panel |
| `npm.local` | `10.10.10.142` | Nginx Proxy Manager admin |
| `tailscale.local` | `10.10.10.102` | Tailscale (if needed) |


## Additional Configuration:

Set your router's DNS server to `10.10.10.2` (AdGuard) so all devices use these local DNS records.

Or manually set DNS on each device to `10.10.10.2`.
