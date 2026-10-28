# Homelab Docker

Docker Compose configuration for my self-hosted services. One host runs today (`hs`); the layout is set up so another host can be added without touching it.

## Hosts

| Host | What it is | Services |
|---|---|---|
| `hs` | Home Server – Ubuntu, Proxmox LXC. Media and data on a Synology NAS mounted under `/home/james/synology` | [compose/hs/stack.yml](compose/hs/stack.yml) |

## Layout

```
docker-compose.yml        Entry point on every host: includes compose/${HOSTNAME}/stack.yml
compose/
  _template.yml           Starting point for a new service
  hs/
    stack.yml             hs networks, secrets, and the list of services it runs
    <service>.yml         One file per service (or group, e.g. immich.yml)
appdata/                  Container data. Only hand-written config is tracked (see .gitignore)
  traefik3/rules/hs/      Traefik file-provider rules: auth chains, middlewares, non-Docker routes
  crowdsec/ homeassistant/ frigate/ homepage/ ...
scripts/
  gen-env-example.sh      Regenerates .env.example from .env
  hs/                     Host scripts (backup-all.sh, temp-unban.sh)
shared/config/bash_aliases  Shell shortcuts (dc, dcup, dclogs, temp-unban, ...)
secrets/                  Docker secret files (not tracked)
.env                      Variables and credentials (not tracked); .env.example lists every key
```

## Everyday use

The repo lives at `/home/james/docker` on the host (`/data/docker` inside the VS Code container). Add the aliases to `~/.bashrc`:

```bash
[ -f "$HOME/docker/shared/config/bash_aliases" ] && . "$HOME/docker/shared/config/bash_aliases"
```

| Command | Does |
|---|---|
| `dcup [service]` | Start or apply changes (`docker compose up -d`) |
| `dcrec service` | Force-recreate a service |
| `dclogs [service]` | Follow logs |
| `dcps` | Status of this host's stack |
| `dccheck` | Validate the compose config |
| `dcplan` | Show which containers `dcup` would recreate |

Watchtower auto-updates containers labelled `com.centurylinklabs.watchtower.enable=true` by recreating them outside Compose, so `dcplan` will list those as "Recreate" even when nothing changed. That's expected; running `dcup` just recreates them on the same image.

## Adding a service

1. Copy [compose/_template.yml](compose/_template.yml) to `compose/hs/<name>.yml` and fill it in.
2. Add `<name>.yml` to the `include:` list in [compose/hs/stack.yml](compose/hs/stack.yml).
3. Put any credentials in `.env`, then run `envexample` (`scripts/gen-env-example.sh`) to update `.env.example`.
4. `dccheck`, then `dcup <name>`.

Conventions:
- Route through Traefik on the `t3_proxy` network; only publish host ports when something outside Docker needs them.
- Auth via a middleware chain: `chain-oauth` (Google, used by most apps), `chain-authelia` (available, used by Traefik's dashboard and Ghost), or `chain-no-auth` for apps with their own login.
- Use `$DOCKERDIR`, `$DATADIR`, `$MEDIADIR`, `$DOWNLOADSDIR` and `$DOMAINNAME` instead of hardcoded paths and domains.
- Pin databases to a major version (e.g. `postgres:16`, `influxdb:2`).

## Adding a host

1. Clone the repo to `~/docker` on the new machine.
2. Create `.env` from `.env.example`, set `HOSTNAME=<newhost>` and its paths and credentials.
3. Create `compose/<newhost>/stack.yml` with that host's networks, secrets and `include:` list. Copy service files from `compose/hs/` as needed.
4. Traefik rules go in `appdata/traefik3/rules/<newhost>/` (Traefik mounts `rules/$HOSTNAME`).
5. `dccheck`, then `dcup`.

## Secrets

- **`secrets/`** – files mounted as Docker secrets (`/run/secrets/...`), declared in each host's `stack.yml`. Used where the image supports `*_FILE` or reads secrets directly (Traefik, OAuth, Authelia, MariaDB, Ghost).
- **`.env`** – everything else: API keys (Homepage widget labels can't read secret files), database passwords, ports and paths. Never commit it.
- App-specific secrets stay in that app's own ignored file, e.g. `appdata/homeassistant/secrets.yaml`.

## CrowdSec: unbanning an IP

If I get locked out away from home (hotel or public wifi), the IP has probably been banned by CrowdSec. The host firewall bouncer and the Traefik bouncer both pull decisions from the CrowdSec LAPI, so removing the decision in CrowdSec clears it everywhere. The web console ([app.crowdsec.net](https://app.crowdsec.net)) shows alerts, but removing decisions needs a paid plan, so use `cscli`.

```bash
temp-unban 1.2.3.4                     # unban + allowlist for 1 week (default)
temp-unban 1.2.3.4 72h "Hotel Paris"   # custom duration and comment
csallow                                # show the temporary allowlist
```

Find the blocked device's public IP with [whatismyip.com](https://whatismyip.com) or `curl -s ifconfig.me`.

Manual commands:

```bash
csdecisions                                         # all active bans
cscli decisions list --ip <IP>                      # is this IP banned?
cscli alerts list --ip <IP>                         # why was it banned?
csinspect <ALERT_ID>                                # full details of an alert
cscli decisions delete --ip <IP>                    # unban
cscli allowlists remove temp-allowlist <IP>         # end a temp-unban early
```

For IPs that should be trusted permanently (home, work, family), add them to [whitelist.yaml](appdata/crowdsec/config/parsers/s02-enrich/whitelist.yaml) and `docker restart crowdsec`.

## Backups

[scripts/hs/backup-all.sh](scripts/hs/backup-all.sh) dumps the Immich and Paperless Postgres databases, then rsyncs the dumps, `appdata/` (minus database folders and caches) and the Immich library to the NAS. Run it as root from cron.

## What gets committed

The repo is private. `.gitignore` tracks everything by default and excludes:
- `.env`, `secrets/`, and secret files inside allowlisted folders (`homeassistant/secrets.yaml`, `authelia/users.yml`, CrowdSec API credentials)
- `backups/`, `logs/`, `.claude/`
- `appdata/` except an explicit allowlist of config files, since it otherwise holds databases, caches and media

To track another `appdata` config file, add a `!` rule for it (and its parent folders) in the APPDATA section. `git check-ignore -v <path>` shows which rule matches a file.
