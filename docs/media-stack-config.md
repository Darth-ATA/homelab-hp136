# Media Stack Configuration Guide - Prowlarr, Sonarr, Radarr, Jellyfin, qBittorrent, Gluetun

## Overview
Configuration guide for your media applications. Language preferences:
- Movies & TV (non-anime): Spanish audio (Spain) with Spanish subtitles, fallback to original + Spanish subs
- Anime: Original audio + Spanish subtitles only (no dub preference)

---

## Language Codes (Radarr/Sonarr)
| Language | Code |
|----------|------|
| Spanish (Spain) | 4 |
| Spanish (Latin America) | 22 |
| English | 1 |
| Original | Special |

---

## 1. Prowlarr Configuration (Port 9696)

Already deployed. Configuration steps:
1. Open http://localhost:9696
2. Go to Settings → Indexers
3. Add your indexers with API keys
4. Enable RSS, Search, Interactive Search

---

## 2. Radarr Configuration (Movies - Port 7878)

### Step 1: Set Language
- Settings → Media Management → Language → Spanish

### Step 2: Custom Formats (Import as JSON)

**CF: Language: Spanish Audio (+15)**
```
{
  "name": "Language: Spanish Audio",
  "includeCustomFormatWhenRenaming": false,
  "specifications": [
    {
      "name": "Spanish",
      "implementation": "LanguageSpecification",
      "negate": false,
      "required": true,
      "fields": { "value": 4 }
    }
  ]
}
```
Score: 15

**CF: Language: Original + Spanish Subs (+10)**
```
{
  "name": "Language: Original + Spanish Subs",
  "includeCustomFormatWhenRenaming": false,
  "specifications": [
    {
      "name": "Original",
      "implementation": "OriginalSpecification",
      "negate": false,
      "required": false
    }
  ]
}
```
Score: 10

**CF: NOT Spanish or Original (-10000)**
```
{
  "name": "Language: Not Spanish or Original",
  "includeCustomFormatWhenRenaming": false,
  "specifications": [
    {
      "name": "Not Spanish",
      "implementation": "LanguageSpecification",
      "negate": true,
      "required": true,
      "fields": { "value": 4 }
    },
    {
      "name": "Not Original",
      "implementation": "OriginalSpecification",
      "negate": true,
      "required": true
    }
  ]
}
```
Score: -10000

### Step 3: Quality Profile
- Settings → Profiles → Quality Profiles
- Create: "HD Bluray + WEB"
- Minimum CF Score: 0
- Language: Spanish

---

## 3. Sonarr Configuration (TV Shows - Port 8989)

### Same as Radarr for non-anime:
- Language: Spanish
- Import same Custom Formats

### OPTIONAL: Separate Anime Sonarr Instance
For anime with original audio + Spanish subs only:
- Create second Sonarr container on port 8990
- Use language: Original (not Spanish)
- This avoids Spanish dubs for anime

---

## 4. Bazarr (Recommended for Spanish Subtitles - Port 6767)

Create compose at /Users/alejandrotorresaguilera/homelab-terraform/docker/bazarr/compose.yml:

```yaml
services:
  bazarr:
    image: linuxserver/bazarr:latest
    container_name: bazarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
    volumes:
      - /root/docker/bazarr/config:/config
      - /data/media:/media
    ports:
      - "6767:6767"
    restart: unless-stopped
```

Configuration:
1. Connect Sonarr (http://sonarr:8989) + Radarr (http://radarr:7878)
2. Settings → Languages: Add Spanish (score 100), English (score 50)
3. Languages Profile: Spanish first, English fallback

---

## 5. Jellyfin Configuration (Ports 8096, 8920)

### Spanish Settings:
1. Dashboard → Settings → Language:
   - Preferred Metadata Language: Español (España)

2. Settings → Playback:
   - Default Subtitle: Spanish (es-ES)
   - Fallback: Latin Spanish (es-MX)

3. Rescan library after changes

---

## 6. qBittorrent + Gluetun (Already Configured)

- qBittorrent UI: http://localhost:8081
- VPN: ProtonVPN Netherlands

### Verify VPN:
```bash
curl --interface gluetun https://api.ipify.org
```

### qBittorrent Settings:
- Language: Español
- Default save: /data/torrents

---

## Docker Services Summary

| Service | Port | Status |
|---------|------|--------|
| Prowlarr | 9696 | ✅ Ready to configure |
| Radarr | 7878 | Add CFs |
| Sonarr | 8989 | Add CFs |
| Jellyfin | 8096/8920 | Configure Spanish |
| qBittorrent | 8081 | ✅ Ready |
| Gluetun | 8081, 6881 | ✅ Ready |

---

## Important Notes

1. Spanish (Spain) is code 4 in Radarr/Sonarr
2. Use Bazarr for automatic Spanish subtitles
3. For anime, prefer original audio with subs - consider separate Sonarr instance
4. Quality profiles should use CF scoring, not language in profile