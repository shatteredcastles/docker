#!/bin/bash
# Refresh the Ghostfolio bearer token used by the Homepage widget.
# Ghostfolio's JWTs expire after ~6 months, and the widget then shows an API
# error. This trades GHOSTFOLIO_ACCESS_TOKEN (the account's security token)
# for a new JWT, writes it to GHOSTFOLIO_BEARER_TOKEN in .env and recreates
# ghostfolio so its homepage.widget.key label picks it up.
# Usage: scripts/hs/ghostfolio-token.sh

set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")/../.."
ENV_FILE="$ROOT/.env"

ACCESS_TOKEN=$(grep '^GHOSTFOLIO_ACCESS_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "GHOSTFOLIO_ACCESS_TOKEN is empty in $ENV_FILE" >&2
    exit 1
fi

# Ghostfolio's port isn't published, so call the API from inside its container
JWT=$(docker exec -e ACCESS_TOKEN="$ACCESS_TOKEN" ghostfolio node -e '
fetch("http://localhost:3333/api/v1/auth/anonymous", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ accessToken: process.env.ACCESS_TOKEN }),
}).then(async (r) => {
  const body = await r.json();
  if (!body.authToken) { console.error(r.status, JSON.stringify(body)); process.exit(1); }
  console.log(body.authToken);
});')

sed -i "s|^GHOSTFOLIO_BEARER_TOKEN=.*|GHOSTFOLIO_BEARER_TOKEN=$JWT|" "$ENV_FILE"

EXPIRES=$(cut -d. -f2 <<< "$JWT" | tr '_-' '/+' | base64 -d 2>/dev/null | grep -o '"exp":[0-9]*' | cut -d: -f2 || true)
echo "Updated GHOSTFOLIO_BEARER_TOKEN${EXPIRES:+ (expires $(date -d "@$EXPIRES" +%F))}"

docker compose --project-directory "$ROOT" up -d ghostfolio
