#!/bin/bash
# Unban an IP in CrowdSec and allowlist it temporarily so it doesn't get re-banned.
# Usage: temp-unban <IP> [duration] [comment]
#   duration defaults to 168h (1 week); accepts CrowdSec durations like 72h, 30m
#   comment defaults to "temp-unban <date>"

set -euo pipefail

CONTAINER="crowdsec"
ALLOWLIST="temp-allowlist"

IP="${1:-}"
DURATION="${2:-168h}"
COMMENT="${3:-temp-unban $(date +%Y-%m-%d)}"

if [ -z "$IP" ] || [ "$IP" = "-h" ] || [ "$IP" = "--help" ]; then
    echo "Usage: temp-unban <IP> [duration=168h] [comment]"
    echo
    echo "Current temporary allowlist:"
    docker exec "$CONTAINER" cscli allowlists inspect "$ALLOWLIST"
    exit 1
fi

# Create the allowlist if it was ever deleted
if ! docker exec "$CONTAINER" cscli allowlists inspect "$ALLOWLIST" >/dev/null 2>&1; then
    docker exec "$CONTAINER" cscli allowlists create "$ALLOWLIST" -d "Temporary allowlist entries"
fi

echo "Active decisions for ${IP}:"
docker exec "$CONTAINER" cscli decisions list --ip "$IP"

docker exec "$CONTAINER" cscli decisions delete --ip "$IP"
docker exec "$CONTAINER" cscli allowlists add "$ALLOWLIST" "$IP" -e "$DURATION" -d "$COMMENT"
docker exec "$CONTAINER" cscli allowlists check "$IP"
