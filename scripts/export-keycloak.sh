#!/usr/bin/env bash
#
# Export the current Keycloak configuration (the running postgres "keycloak"
# database) into keycloak_dump.sql. That file is mounted into the postgres
# container's /docker-entrypoint-initdb.d, so it re-seeds the realm on every
# fresh container (the data dir is tmpfs). Run this after changing realms,
# clients, or users in the Keycloak admin console to persist those changes.
#
# Usage:
#   scripts/export-keycloak.sh

set -euo pipefail

# Resolve repo root from this script's location so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVICE="postgres"        # docker compose service name
DB_USER="keycloak"
DB_NAME="keycloak"
OUT_FILE="${REPO_ROOT}/keycloak_dump.sql"

cd "${REPO_ROOT}"

# Ensure the postgres service is up before attempting a dump.
if [ -z "$(docker compose ps -q "${SERVICE}" 2>/dev/null)" ]; then
  echo "error: compose service '${SERVICE}' is not running. Start it with 'docker compose up -d ${SERVICE} keycloak' first." >&2
  exit 1
fi

echo "Dumping '${DB_NAME}' database from service '${SERVICE}'..."

# Write to a temp file first so a failed dump never truncates the existing one.
# -T disables TTY allocation so the redirect captures clean output.
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

docker compose exec -T "${SERVICE}" \
  pg_dump --username "${DB_USER}" --no-password "${DB_NAME}" > "${TMP_FILE}"

if [ ! -s "${TMP_FILE}" ]; then
  echo "error: pg_dump produced an empty file; aborting without overwriting ${OUT_FILE}." >&2
  exit 1
fi

mv "${TMP_FILE}" "${OUT_FILE}"
trap - EXIT

echo "Wrote $(wc -l < "${OUT_FILE}") lines to ${OUT_FILE}"
