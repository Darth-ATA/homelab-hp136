# Nginx Proxy Manager Configuration

Access NPM at: http://192.168.1.142:81

Default login: `admin@example.com` / `changeme` (change on first login)

## Configure Home Assistant Proxy Host:

1. Go to **Proxy Hosts** tab
2. Click **Add Proxy Host**
3. Fill in the details:

### Proxy Host Configuration:

| Field | Value |
|-------|-------|
| Domain Names | `homeassistant.local` |
| Scheme | `http` |
| Forward Hostname / IP | `192.168.1.100` |
| Forward Port | `8123` |
| Cache Assets | ☐ (optional) |
| Block Common Exploits | ☑ |
| Websockets Support | ☑ (CRITICAL for Home Assistant) |
| SSL | ☐ (use only if you have a certificate) |

4. Click **Save**

## Test:

After configuration, you should be able to access Home Assistant at:
- `http://homeassistant.local`

## Optional: Add More Services

Repeat the process for other services:
- `adguard.local` → `192.168.1.2:80`
- `npm.local` → `192.168.1.142:81` (or use NPM's own management)
