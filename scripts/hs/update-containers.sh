#!/bin/bash
# Pull and recreate every service labelled homelab.auto-update=true, prune the
# images that replaced, and send a Pushover summary. Everything else is left to
# Diun notifications and manual updates.
#
# Run weekly from the host's crontab (crontab -e):
#   0 4 * * 0  $HOME/docker/scripts/hs/update-containers.sh >> $HOME/docker/logs/update-containers.log 2>&1
#
# Usage: update-containers.sh [--dry-run]

set -uo pipefail

ROOT="$(readlink -f "$(dirname "$(readlink -f "$0")")/../..")"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

dc() { docker compose --project-directory "$ROOT" "$@"; }
log() { echo "$(date '+%F %T') $*"; }
env_var() { grep -m1 "^$1=" "$ROOT/.env" | cut -d= -f2- | tr -d '"'; }

notify() {
    local token user
    token=$(env_var PUSHOVER_APP_TOKEN); user=$(env_var PUSHOVER_USER_KEY)
    [ -n "$token" ] && [ -n "$user" ] || return 0
    curl -s -o /dev/null --form-string "token=$token" --form-string "user=$user" \
        --form-string "title=$(env_var HOSTNAME) container updates" --form-string "message=$1" \
        https://api.pushover.net/1/messages.json
}

image_of() { docker inspect --format '{{.Image}}' "$(dc ps -q "$1" 2>/dev/null | head -1)" 2>/dev/null; }

# Services carrying the label in the resolved compose config
mapfile -t services < <(dc config 2>/dev/null | awk '
    /^services:/                      { in_svc = 1; next }
    /^[^ ]/                           { in_svc = 0 }
    in_svc && /^  [A-Za-z0-9._-]+:$/  { svc = substr($1, 1, length($1) - 1) }
    in_svc && /homelab\.auto-update: "true"/ { print svc }' | sort -u)

if [ ${#services[@]} -eq 0 ]; then
    log "No services labelled homelab.auto-update=true (or compose config failed)"
    notify "Auto-update found no services - check compose config"
    exit 1
fi

log "Auto-updating ${#services[@]} services: ${services[*]}"
if [ $DRY_RUN -eq 1 ]; then
    log "Dry run - what 'up' would change:"
    dc up -d --no-deps --dry-run "${services[@]}" 2>&1 | grep -E "Recreate|Create " | grep -v "d $"
    exit 0
fi

declare -A before
for s in "${services[@]}"; do before[$s]=$(image_of "$s"); done

failed=""
dc pull --quiet --ignore-pull-failures "${services[@]}" || failed="pull"
dc up -d --no-deps "${services[@]}" || failed="${failed:+$failed, }up"

updated=()
for s in "${services[@]}"; do
    [ "${before[$s]}" != "$(image_of "$s")" ] && updated+=("$s")
done

docker image prune -f >/dev/null

if [ -n "$failed" ]; then
    log "FAILED during: $failed. Updated: ${updated[*]:-none}"
    notify "Auto-update had errors ($failed). Updated: ${updated[*]:-none}. See logs/update-containers.log"
    exit 1
fi

log "Done. Updated: ${updated[*]:-none}"
[ ${#updated[@]} -gt 0 ] && notify "Updated ${#updated[@]}: ${updated[*]}"
exit 0
