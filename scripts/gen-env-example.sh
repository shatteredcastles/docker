#!/bin/bash
# Regenerate .env.example from .env: same keys and sections, credential values blanked.
# Usage: scripts/gen-env-example.sh

set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")/.."
SRC="$ROOT/.env"
DEST="$ROOT/.env.example"

# Keys whose values are secret or specific to this network
SENSITIVE='(PASS|PASSWORD|KEY|TOKEN|SECRET|USERNAME|ADMIN_USER|_URL|PUBLIC_IP|_EMAIL|_FROM)$'

while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        key="${BASH_REMATCH[1]}"
        if [[ "$key" =~ $SENSITIVE ]]; then
            echo "$key="
        else
            echo "$line"
        fi
    else
        echo "$line"
    fi
done < "$SRC" > "$DEST"

echo "Wrote $DEST ($(grep -c '=' "$DEST") variables)"
