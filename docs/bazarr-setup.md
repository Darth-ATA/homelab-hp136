# Bazarr Setup Guide

## Overview
Bazarr is a companion service to Sonarr and Radarr that automatically downloads subtitles for TV shows and movies.

## Infrastructure
- **Proxmox Host**: 192.168.1.134
- **Docker LXC**: 101 (192.168.1.142)
- **Bazarr Web UI**: http://192.168.1.142:6767
- **Config path**: `/root/docker/bazarr/config/`
- **DB path**: `/root/docker/bazarr/config/db/bazarr.db`

## Deployment

Already in `docker/bazarr/compose.yml`. Container connects to the `arrsuite` Docker network.

## First-Time Setup (via Web UI)

Follow the [TRaSH Guide](https://trash-guides.info/Bazarr/After-install-configuration/) for the official walkthrough.

### 1. Configure Providers

**Settings → Providers**

#### OpenSubtitles.com
- Create a free account at [opensubtitles.com](https://www.opensubtitles.com)
- In Bazarr, enter your **username** and **account password** (NOT an API key)
- Bazarr includes a built-in API consumer key. If you generated your own API consumer on opensubtitles.com, put the key in the password field alongside your username
- ⚠️ If you get `AuthenticationError: Login failed`, clear the cache (`/root/docker/bazarr/config/cache/`) and restart Bazarr

#### Podnapisi
- No credentials required
- May fail with `ConnectionError` if the site is unreachable (transient)

### 2. Configure Languages

**Settings → Languages**
- Enable Spanish (and any other desired languages)
- Create a **language profile** (e.g. "Español") with the desired languages
- Bazarr uses Python `ast.literal_eval()` internally — profiles created through the UI always have the correct format

### 3. Assign Profile to Existing Content

**Series → Mass Edit**
- Select all → assign the language profile → Save
**Movies → Mass Edit**
- Select all → assign the language profile → Save

Bazarr only auto-searches subtitles for content added **after** assigning the profile. For existing content, use **Wanted → Search All** after assigning.

## Critical: Do NOT Edit the Database Directly

Bazarr's SQLite DB (`bazarr.db`) uses Python-specific serialization:

- `missing_subtitles` column stores Python lists as strings, parsed via `ast.literal_eval()`
  - **Correct**: `'[]'` or `'["es:Spanish"]'`
  - **Wrong**: `'"es:Spanish"'` (JSON-style) — will crash
- `table_languages_profiles.items` requires an `id` field per entry:
  ```json
  [{"id": 1, "language": {"code": "es", "name": "Spanish"}, "forced": false, "hi": false}]
  ```
- Missing `id` crashes `health.py:71` with `KeyError: 'id'`

**Use the UI for all language/profile configuration.** If the DB breaks, reset the affected rows to defaults and recreate profiles through the UI.

## Recovering from a Broken DB

If Bazarr starts but APIs return HTTP 500:

1. Check logs: `docker logs bazarr | grep ERROR`
2. Common cause: corrupted `missing_subtitles` or bad language profiles
3. Reset broken series to default profile (profileId=0):
   ```sql
   UPDATE table_episodes SET missing_subtitles='[]' WHERE missing_subtitles='es:Spanish';
   DELETE FROM table_languages_profiles WHERE profileId=<bad_id>;
   ```
4. Restart Bazarr and reconfigure through UI
5. Clear cache (`/root/docker/bazarr/config/cache/`) if throttling persists

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `AuthenticationError: Login failed` | Invalid OpenSubtitles credentials | Update in Settings → Providers, clear cache |
| `Bad status code: 302` | Expired API key or wrong password | Use account password, not API consumer key |
| `All providers are throttled` | Repeated auth failures | Clear cache + restart Bazarr |
| `Invalid session` (WebSocket) | Benign, Bazarr logs it at INFO level after first occurrence | Ignore |
