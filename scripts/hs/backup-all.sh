#!/bin/bash

# Configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# Assuming .env is two levels up from scripts/hs/
DOTENV_FILE="$(readlink -f "${SCRIPT_DIR}/../../.env")"

# Sourcing environment variables robustly
if [ -f "$DOTENV_FILE" ]; then
    echo "Sourcing environment variables from ${DOTENV_FILE}"
    # Helper to extract variables while handling spaces and special characters
    get_env_var() {
        grep "^${1}=" "$DOTENV_FILE" | head -n1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }

    DOCKERDIR=$(get_env_var "DOCKERDIR")
    DATADIR=$(get_env_var "DATADIR")
    HOSTNAME=$(get_env_var "HOSTNAME")
    IMMICH_DB_USER=$(get_env_var "IMMICH_DB_USER")
    IMMICH_DB_NAME=$(get_env_var "IMMICH_DB_NAME")
    PAPERLESS_DB_USER=$(get_env_var "PAPERLESS_DB_USER")
    PAPERLESS_DB_NAME=$(get_env_var "PAPERLESS_DB_NAME")

    # Fallbacks if extraction failed
    DOCKERDIR="${DOCKERDIR:-/home/james/docker}"
    DATADIR="${DATADIR:-/home/james/synology/data}"
    HOSTNAME="${HOSTNAME:-hs}"
    IMMICH_DB_USER="${IMMICH_DB_USER:-postgres}"
    IMMICH_DB_NAME="${IMMICH_DB_NAME:-immich}"
    PAPERLESS_DB_USER="${PAPERLESS_DB_USER:-paperless}"
    PAPERLESS_DB_NAME="${PAPERLESS_DB_NAME:-paperless}"
else
    echo "Error: .env file not found at ${DOTENV_FILE}"
    exit 1
fi

# Use inherited variables or set defaults
BACKUP_DIR="${DOCKERDIR}/backups"
NAS_BACKUP_DIR="${DATADIR}/backups/${HOSTNAME}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RETENTION_DAYS=7

# Ensure local backup dirs exist
mkdir -p "${BACKUP_DIR}/immich/db"
mkdir -p "${BACKUP_DIR}/paperless/db"

echo "Starting backup at $(date)"

# 1. Immich Database Backup
echo "Backing up Immich database..."
docker exec immich_postgres pg_dump -U "${IMMICH_DB_USER}" "${IMMICH_DB_NAME}" | gzip > "${BACKUP_DIR}/immich/db/immich_db_${TIMESTAMP}.sql.gz"

# 2. Paperless Database Backup
echo "Backing up Paperless database..."
docker exec paperless_db pg_dump -U "${PAPERLESS_DB_USER}" "${PAPERLESS_DB_NAME}" | gzip > "${BACKUP_DIR}/paperless/db/paperless_db_${TIMESTAMP}.sql.gz"

# 3. Sync to NAS
echo "Syncing appdata and media to NAS..."

# Note: We use -rltz (no -p, -o, -g, -D) to avoid permission, ownership, and special file errors on NAS mounts
# Note: This script should be run as a user with read access to appdata (e.g., as root via cron)
RSYNC_FLAGS="-rltz"

# Sync local DB dumps
rsync $RSYNC_FLAGS --delete "${BACKUP_DIR}/" "${NAS_BACKUP_DIR}/db_dumps/"

# Sync appdata
# Exclude database directories as they are backed up via pg_dump
# Also exclude large media metadata, caches, and logs for speed
rsync $RSYNC_FLAGS --delete "${DOCKERDIR}/appdata/" "${NAS_BACKUP_DIR}/appdata/" \
    --exclude 'immich/upload' \
    --exclude 'immich/postgres*' \
    --exclude 'paperless/db' \
    --exclude 'plex' \
    --exclude 'jellyfin' \
    --exclude 'firefox' \
    --exclude 'immich/model-cache' \
    --exclude '**/cache' \
    --exclude '**/logs' \
    --exclude '**/MediaCover' \
    --exclude '**/Backups'

# Sync Immich Library (might be large)
rsync $RSYNC_FLAGS --delete "${DOCKERDIR}/appdata/immich/upload/" "${NAS_BACKUP_DIR}/immich_library/"

# 4. Cleanup old local backups
find "${BACKUP_DIR}" -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete

echo "Backup completed successfully at $(date)"

