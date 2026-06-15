## Torrentio Setup Guide for Prowlarr

### Overview
Torrentio is a Stremio add-on that aggregates torrents from multiple providers. When configured as a Prowlarr indexer, it allows Sonarr/Radarr to search and download content through Torrentio's providers.

### Prerequisites
- Prowlarr running at http://192.168.1.142:9696
- API Key: `<your-prowlarr-api-key>`
- SSH access to Proxmox: `ssh -i ~/.ssh/homelab_key root@192.168.1.134`

---

## Method 1: Using the Working Config File

### Step 1: Create the Config Directory
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- mkdir -p /config/custom"
```

### Step 2: Copy the Working Config
Copy the contents from `docker/prowlarr/custom/torrentio.yml` to `/config/custom/torrentio.yml` in the Prowlarr container:

```bash
scp docker/prowlarr/custom/torrentio.yml root@192.168.1.134:/tmp/torrentio.yml
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- mkdir -p /root/docker/prowlarr/config/custom && \
   pct push 101 /tmp/torrentio.yml /root/docker/prowlarr/config/custom/torrentio.yml"
```

### Step 3: Restart Prowlarr
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- docker restart prowlarr"
```

### Step 4: Enable in Prowlarr UI
1. Open http://192.168.1.142:9696
2. Go to Settings → Indexers
3. Click "+" → Add from Custom
4. Find "Torrentio" → Enable all capabilities
5. Save and test with a search

---

## Method 2: Manual Configuration

### Create torrentio.yml manually:

```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- cat > /config/custom/torrentio.yml << 'EOF'
---
id: torrentio
name: Torrentio
description: "Torrentio Indexer"
language: en-US
type: public
encoding: UTF-8
followredirect: false
testlinktorrent: false
requestDelay: 2
links:
  - https://torrentio.strem.fun/

caps:
  categories:
    Movies: Movies
    TV: TV

  modes:
    search: [q]
    movie-search: [q, imdbid]
    tv-search: [q, imdbid, season, ep]
  allowrawsearch: false

settings:
  - name: default_opts
    type: text
    label: Torrentio Options
    default: "providers=eztv,rarbg,1337x,thepiratebay,kickasstorrents,torrentgalaxy,magnetdl,horriblesubs,nyaasi,tokyotosho,anidex,rutor,rutracker,comando,bludv,torrent9,ilcorsaronero,mejortorrent,wolfmax4k,cinecalidad,besttorrents|sort=qualitysize|qualityfilter=scr,cam"
  - name: debrid_provider_key
    type: text
    label: Debrid provider API Key
    default: ""
  - name: debrid_provider
    type: select
    label: Debrid provider
    default: none
    options:
      none: None
      realdebrid: Real-Debrid
      alldebrid: AllDebrid
      premiumize: Premiumize
      debridlink: Debridlink
      offcloud: Offcloud
      putio: Put.io
      torbox: Torbox
  - name: validate_imdb_movie
    type: text
    label: IMDB ID of Movie to use for Radarr validation
    default: "tt0137523"
  - name: validate_imdb_tv
    type: text
    label: IMDB ID TV show to use for Sonarr validation
    default: "tt9288030"

search:
  headers:
    User-Agent:
      [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0",
      ]
  paths:
    - path: "{{ if .Query.IMDBID }}{{ .Config.default_opts }}|{{ .Config.debrid_provider }}={{ .Config.debrid_provider_key }}/stream/movie/tt{{ .Query.IMDBID }}.json{{ else }}providers=rarbg,1337x|sort=size|qualityfilter=brremux,hdrall,dolbyvision,4k,720p,480p,other,scr,cam,unknown|{{ .Config.debrid_provider }}={{ .Config.debrid_provider_key }}/stream/movie/{{ .Config.validate_imdb_movie }}.json{{ end }}"
      method: get
      response:
        type: json
        noResultsMessage: '"streams": []'
      categories: [Movies]
    - path: "{{ if .Query.IMDBID }}{{ .Config.default_opts }}{{else}}providers=rarbg,1337x|sort=size|qualityfilter=brremux,hdrall,dolbyvision,4k,720p,480p,other,scr,cam,unknown{{ end }}|{{ .Config.debrid_provider }}={{ .Config.debrid_provider_key }}/stream/series/tt{{ if .Query.IMDBID }}{{ .Query.IMDBID}}{{ else }}{{ .Config.validate_imdb_tv }}{{ end }}:{{ if .Query.Season }}{{ .Query.Season }}{{ else }}1{{ end }}:{{ if .Query.Ep }}{{ .Query.Ep }}{{ else }}1{{ end }}.json"
      method: get
      response:
        type: json
        noResultsMessage: '"streams": []'
      categories: [TV]

  rows:
    selector: streams
    missingAttributeEqualsNoResults: true

  fields:
    title:
      selector: title
      filters:
        - name: split
          args: ["\n", 0]
    year:
      selector: title
      filters:
        - name: regexp
          args: "(\\b(19|20)\\d\\d\\b)"
    category_is_tv_show:
      text: "{{ .Result.title }}"
      filters:
        - name: regexp
          args: "\\b(S\\d+(?:E\\d+)?)\\b"
    category:
      text: "{{ if .Result.category_is_tv_show }}TV{{ else }}Movies{{ end }}"
    infohash:
      selector: infoHash
    seeders:
      selector: title
      filters:
        - name: regexp
          args: "👤 (\\d+)"
    leechers:
      text: "0"
    size:
      selector: title
      filters:
        - name: regexp
          args: "💾 (\\d+(?:\\.\\d+)? [KMGT]B)"
EOF"
```

### Step 2: Restart Prowlarr
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- docker restart prowlarr"
```

---

## Testing the Configuration

### Test Movie Search
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- curl -s 'https://torrentio.strem.fun/providers=eztv,rarbg|thepiratebay,torrentgalaxy,magnetdl,horriblesubs,nyaasi,anidex/stream/movie/tt0137523.json' | jq '.streams | length'"
```
Expected: 10+ results

### Test TV Series Search (anime example)
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- curl -s 'https://torrentio.strem.fun/providers=eztv,rarbg/thepiratebay,kickasstorrents,torrentgalaxy,magnetdl,horriblesubs,nyaasi,tokyotosho,anidex/stream/series/tt9529546:1:1.json' | jq '.streams | length'"
```
Expected: 20+ results (The Rising of the Shield Hero)

---

## Optional: Enable Real-Debrid for Better Results

Without debrid, Torrentio only returns direct torrents. Real-Debrid provides access to cached content from premium linkers.

### Step 1: Get API Key
1. Go to https://real-debrid.com/account → API
2. Copy your API key

### Step 2: Configure in Prowlarr
1. Settings → Indexers → Edit Torrentio
2. Set "Debrid provider" to "Real-Debrid"
3. Enter your API key in "Debrid provider API Key"

---

## Troubleshooting

### Issue: 0 Results from Search

**Symptoms:** Searches return no results even though content exists

**Check 1: IMDB ID Format**
Torrentio requires IMDB IDs with 'tt' prefix. Verify the config has:
```
stream/series/tt{{ .Query.IMDBID }}
```

**Check 2: Verify API Works**
```bash
# Direct test without debrid
curl -s 'https://torrentio.strem.fun/providers=eztv,rarbg/stream/series/tt9529546:1:1.json' | jq '.streams | length'
```

**Check 3: Prowlarr Logs**
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 \
  "pct exec 101 -- docker logs prowlarr --tail 50 | grep -i torrentio"
```

### Issue: Indexer Validation Fails

**Symptoms:** Can't enable the indexer in Prowlarr UI

**Fix:** Update validation IMDB IDs to match content available on Torrentio:
- Movie: `tt0137523` (Fight Club - should exist everywhere)
- TV: `tt9288030` (Reacher S02 - should exist on RARBG)

---

## Recommended Providers

The default config includes these providers:
- **eztv** - TV torrents
- **rarbg** - High-quality releases
- **horriblesubs/nyaasi/tokyotosho/anidex** - Anime specific
- **thepiratebay, kickasstorrents** - General
- **torrentgalaxy, magnetdl** - Backup

Remove or add providers by editing the `default_opts` in the config.

---

## Key Files

- Working config: `docker/prowlarr/custom/torrentio.yml`
- Troubleshooting: `docs/download-pipeline-troubleshooting.md`

---

## References

- Prowlarr Custom Indexers: https://github.com/dreulavelle/Prowlarr-Indexers
- Torrentio: https://torrentio.strem.fun/
- TRaSH Guides: https://trash-guides.info/