#!/usr/bin/env bash
# Dev entrypoint: fetch deps, wait for Postgres, set up the DB (create + migrate
# via Ash) as the privileged user, create the restricted app role, then boot the
# Phoenix server AS the restricted role (subject to RLS, ADR-018). Idempotent.
set -euo pipefail

DB_HOST="${DATABASE_HOST:-db}"
DB_NAME="${DATABASE_NAME:-movimento_dev}"
ADMIN_USER="${DATABASE_USER:-postgres}"
ADMIN_PASS="${DATABASE_PASSWORD:-postgres}"
APP_USER="${DATABASE_APP_USER:-movimento_app}"
APP_PASS="${DATABASE_APP_PASSWORD:-movimento_app}"

echo "==> mix deps.get"
mix deps.get

echo "==> waiting for postgres at ${DB_HOST}:5432"
until pg_isready -h "${DB_HOST}" -p 5432 -U "${ADMIN_USER}" >/dev/null 2>&1; do
  sleep 1
done

echo "==> mix ash.setup (create + migrate, as ${ADMIN_USER})"
mix ash.setup

echo "==> setup restricted app role (${APP_USER}) + grants + RLS (as ${ADMIN_USER})"
PGPASSWORD="${ADMIN_PASS}" psql -h "${DB_HOST}" -U "${ADMIN_USER}" -d "${DB_NAME}" \
  -v ON_ERROR_STOP=1 -q -f priv/sql/setup_app_role.sql

echo "==> mix phx.server (as ${APP_USER}, subject to RLS)"
exec env DATABASE_USER="${APP_USER}" DATABASE_PASSWORD="${APP_PASS}" mix phx.server
