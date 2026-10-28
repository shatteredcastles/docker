# Docker Compose Examples

This repository contains Docker Compose snippets for several hosts. You'll find example stacks for `hs`, `ds918`, `mds`, `dns`, and `ws` alongside helper scripts and sample configuration files.

## Getting Started

Clone the repository and copy any `.example` files to customize settings:

```bash
git clone https://github.com/USERNAME/docker.git
cd docker
cp .env.example .env # if present
```

Bring up the home server stack:

```bash
docker compose -f docker-compose-hs.yml up -d
```

Compose files under `compose/` can be mixed and matched for other hosts.

## Repository Layout

- `docker-compose-hs.yml` – main stack used on the home server
- `compose/` – per-host Docker Compose snippets
- `scripts/` – helper scripts
- `appdata/` – sample application configs
- `shared/` – shared assets such as `bash_aliases`

## Understanding This Repository

## My Setup

I have 5 docker hosts. I sync all my Docker stacks using Syncthing and push the files to GitHub so I can share with the community. 

- **_docker-compose-hs.yml:_** Docker Compose for <u>Home Server</u> on Ubuntu Server Proxmox LXC Container.
- **_docker-compose-mds.yml:_** Docker Compose for <u>Media/Database Server</u> on Ubuntu Server Proxmox LXC Container.
- **_docker-compose-dns.yml:_** Docker Compose for <u>AdBlock/ DNS Server</u> on Raspberry Pi 4B.
- **_docker-compose-ws.yml:_** Docker Compose for <u>Web Server</u> on Digital Ocean VPS, which powers this website.
- **_docker-compose-ds918.yml:_** Docker Compose for <u>Synology DS918+</u> NAS.

Syncing also allows me to have a backup of one system's configuration file in all the other hosts. For this reason, where applicable, I segregate or name files/folders with their hostname (for example: **_hs_** for Home Server).

Almost any app/service from the docker-compose files listed above can be copy-pasted to any other compose file in this repo.

## Archives
Files and folders inside _archives_ are not actively maintained. But they may still provide a good starting point. 

## What apps are included in this stack?

The apps I use are scattered around in several different docker-compose files. Click the links below for specific installation guides.

Some apps are used in more than one host and some on only one. 

**This is not an exhaustive list**

### FRONTENDS

- Traefik - Reverse Proxy
- Nginx Proxy Manager - Reverse Proxy 
- Docker Socket Proxy - Secure Proxy for Docker API
- [OAuth](https://www.smarthomebeginner.com/traefik-forward-auth-google-oauth-2022/) - Google OAuth 2 Forward Authentication
- [Authelia](https://www.smarthomebeginner.com/docker-authelia-tutorial/) - Private Forward Authentication
- [Portainer](https://www.smarthomebeginner.com/portainer-docker-compose-guide/) - Container Management
- Organizr - Dashboard for Apps
- Heimdall - Dashboard for Apps
- Homepage - Dashboard for Apps
- Dashy - Dashboard for Apps
- Autoindex - Plain text Index to All Files

### SMART HOME

- Home Assistant Core - Home Automation
- HA-Dockermon - Manage Docker containers in Home Assistant
- Mosquitto - MQTT Broker
- [MotionEye](https://www.smarthomebeginner.com/motioneye-docker-guide/) - Video Surveillance
- [Frigate](https://www.smarthomebeginner.com/frigate-docker-guide/) - Video Surveillance
- [ZoneMinder](https://www.smarthomebeginner.com/zoneminder-docker-guide/) - Video Surveillance
- MiFlora - MiFlora MQTT Daemon (MiFlora Plant Sensors)

### DATABASE

- MariaDB - MySQL Database
- phpMyAdmin - Database management
- [InfluxDB](https://www.smarthomebeginner.com/influxdb-docker-compose-guide/) - Database for sensor data
- Postgres - Database
- [Grafana](https://www.smarthomebeginner.com/grafana-docker-compose-guide/) - Graphical data visualization for InfluxDB data
- Varken - Monitor Plex, Sonarr, Radarr, and Other Data
- [Redis](https://www.smarthomebeginner.com/redis-docker-compose-example/) - Key value store
- Redis Commander - Redis management

### DOWNLOADERS

- jDownloader - Download management
- TransmissionBT with VPN - Torrent Downloader.
- SABnzbd - Binary newsgrabber, NZB downloader
- Nzbget - Binary newsgrabber, NZB downloader
- [qBittorrent](https://www.smarthomebeginner.com/gluetun-docker-guide/) with Wireguard VPN from [Surfshark](https://bit.ly/shb-surfshark) - Torrent downloader

### INDEXERS

- NZBHydra2 - NZB meta search 
- Jackett - Torrent proxy
- Prowlarr - Torrent proxy

### PVRS

- Lidarr - Music Management
- Radarr - Movie management
- Sonarr - TV Shows management
- LazyLibrarian - Books Management
- Readarr - Books Management

### MEDIA SERVER

- AirSonic Advanced - Music Server
- NaviDrome - Music Server
- FunkWhale - Music Server
- Calibre - Ebook/Audiobook Server
- Calibre-Web - Ebook/Audiobook Reader
- [Plex](https://www.smarthomebeginner.com/plex-docker-compose/) - Media Server
- Emby - Media Server
- [Jellyfin](https://www.smarthomebeginner.com/jellyfin-docker-compose/) - Media Server
- Ombi - Media Requests
- Tautulli - Previously PlexPy. Plex statistics and monitoring
- Plex-Sync - For Syncing watched status between plex servers
- PhotoShow - Personal Photo Gallery and viewer
- TellyTv- IPTV proxy for Plex
- xTeve- IPTV proxy for Plex

### MEDIA FILE MANAGEMENT

- Bazarr - Subtitle Management
- Picard - Music Library Tagging and Management
- Handbrake - Video Conversion, Transcoding, and Compression
- MKVToolNix - Video Editing, Remuxing (changing media container while keeping original source quality)
- MakeMKV - Video Editing (Ripping from Disks)
- FileBot - File renamer
- Tiny Media Manager - Media Files Management

### UTILITIES

- Firefox - Web Broswerstack
- Glances - System Information
- APCUPSD - APC UPS Management
- [Guacamole](https://www.smarthomebeginner.com/install-guacamole-on-docker/) - Remote desktop, SSH, on Telnet on any HTML5 Browser
- Guacamole Daemon - Needed for Guacamole
- [Dozzle](https://www.smarthomebeginner.com/dozzle-docker-compose-guide/) - Docker logs viewer
- qDirStat - Directory Statistics
- StatPing - Status Page & Monitoring Server
- SmokePing - Network Latency Monitoring
- VS Code Server - Code Editor
- Logarr - Log Management
- Monitorr - Webfront to display the status of any webapp or service
- Cloud Commander - Web File Manager
- Cloud9 - Cloud IDE
- SMTP To Telegram - Sends all incoming Email messages to Telegram
- UniFi Controller - Controller for Ubiquiti UniFi Network Gear
- Rclone - Mount Cloud/Google Drive
- MergerFS - Merge local and remote file systems
- [Gluetun](https://www.smarthomebeginner.com/gluetun-docker-guide/) - VPN client for docker containers and more
- [DeUnhealth](https://www.smarthomebeginner.com/gluetun-docker-guide/) - Auto restart containers on VPN restart
- [AdGuard Home](https://www.smarthomebeginner.com/adguard-home-docker-compose-guide/) - DNS Sinkhole / Ad-blocker

### WEB

- Nginx - Web Server
- php7 - PHP-FPM

### MAINTENANCE

- Watchtower - Automatic Docker Container Updates
- Docker-GC - Automatic Docker Garbage Collection
- Traefik Certificate Dumper - Extract Traefik SSL Certs
- Cloudflare DDNS - Dynamic IP Updater
- Cloudflare Companion - Automatic CNAME creation for services
- WhoAmI - For testing.

## Bash Aliases 

I use bash_aliases to simplify starting and stopping containers/stack. Included in the repo is an example of bash_aliases I use (replace USER with your Linux username). 

Download it to a known location (e.g. /home/user/docker/shared/config/). Then add the following code block to `.bashrc` file in the user's home folder.

```
if [ -f "$HOME/docker/shared/config/bash_aliases" ]; then
    . $HOME/docker/shared/config/bash_aliases
fi
```
Here are some example alias commands:

- `dcup` - Start Docker Traefik 2 stack
- `dcdown` - Stop Docker Traefik 2 stack
- `dcrec` - Start or recreate a specific service or the full stack
- `dcstop` - Stop a specific service or the full stack
- `dcrestart` - Restart a specific service or the full stack
- `dclogs` - See real-time logs for the corresponding stack or service
- `dcpull` - Pull new images for the corresponding stack or service

## CrowdSec: Unbanning an IP

If I get locked out while away from home (hotel or public wifi), the IP has probably been banned by CrowdSec. Bans are enforced by both the host firewall bouncer and the Traefik bouncer, but both pull from the CrowdSec LAPI, so removing the decision in CrowdSec clears it everywhere.

The CrowdSec web console ([app.crowdsec.net](https://app.crowdsec.net)) shows alerts, but removing decisions requires a paid plan, so unbanning is done with `cscli`.

### Quick unban: `temp-unban`

`scripts/hs/temp-unban.sh` removes any active ban on an IP and adds it to the `temp-allowlist` with an expiry, so it doesn't get re-banned. Add an alias to `.bashrc`:

```bash
alias temp-unban='/data/docker/scripts/hs/temp-unban.sh'
```

Usage:

```bash
temp-unban 1.2.3.4                     # unban + allowlist for 1 week (default)
temp-unban 1.2.3.4 72h                 # custom duration
temp-unban 1.2.3.4 72h "Hotel Paris"   # custom comment
temp-unban                             # show current temp allowlist
```

Find the current public IP from the blocked device with [whatismyip.com](https://whatismyip.com) or `curl -s ifconfig.me`.

### Manual commands

```bash
docker exec crowdsec cscli decisions list                    # all active bans
docker exec crowdsec cscli decisions list --ip <IP>          # is this IP banned?
docker exec crowdsec cscli alerts list --ip <IP>             # why was it banned?
docker exec crowdsec cscli alerts inspect <ALERT_ID> -d      # full details of an alert
docker exec crowdsec cscli decisions delete --ip <IP>        # unban

docker exec crowdsec cscli allowlists inspect temp-allowlist             # view temp allowlist
docker exec crowdsec cscli allowlists remove temp-allowlist <IP>         # remove early
```

For IPs that should be trusted permanently (home, work, family), add them to `appdata/crowdsec/config/parsers/s02-enrich/whitelist.yaml` and run `docker restart crowdsec`.

## What Gets Committed

This repo is private, but `.gitignore` still uses an allowlist approach: everything is ignored by default (`*` and `*/`) and files are explicitly re-included with `!` rules. This keeps app data, databases, logs, and secrets out of git automatically.

To start tracking a new file, add a `!` rule for it (and for its parent folder if needed). For example, `scripts/hs/` only tracks `*.example` files plus specific scripts:

```gitignore
!scripts/hs
scripts/hs/*
!scripts/hs/*.example
!scripts/hs/temp-unban.sh
```

Use `git check-ignore -v <path>` to see which rule is ignoring a file.

Things that should never be committed: `.env`, `secrets/`, `appdata/homeassistant/secrets.yaml`, and CrowdSec `*_api_credentials.yaml`.

## Further Reading

- [Traefik Docker Security Best Practices](https://www.smarthomebeginner.com/traefik-docker-security-best-practices/)
- [Crowdsec Docker Compose Guide Part 1](https://www.smarthomebeginner.com/crowdsec-docker-compose-1-fw-bouncer/)
- [CrowdSec Docker Part 2: Cloudflare Bouncer](https://www.smarthomebeginner.com/crowdsec-cloudflare-bouncer/)
- [CrowdSec Docker Part 3: Traefik Bouncer](https://www.smarthomebeginner.com/crowdsec-traefik-bouncer/)
- [CrowdSec Multiserver Docker](https://www.smarthomebeginner.com/crowdsec-multiserver-docker/)
- [How to Install Docker and Docker Compose](https://www.smarthomebeginner.com/install-docker-on-ubuntu-22-04/)
- [Cloudflare Settings for Traefik Docker](https://www.smarthomebeginner.com/cloudflare-settings-for-traefik-docker/)
- [Ultimate Docker to Podman Migration Guide](https://www.smarthomebeginner.com/docker-to-podman-migration-guide/)
- [Nextcloud Docker with Traefik Reverse Proxy](https://www.smarthomebeginner.com/traefik-docker-nextcloud/)
