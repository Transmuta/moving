#!/usr/bin/env bash
# Dev entrypoint: fetch deps, wait for Postgres, set up the DB (create + migrate
# via Ash), then boot the Phoenix server. Idempotent — safe to re-run.
set -euo pipefail

echo "==> mix deps.get"
mix deps.get

echo "==> waiting for postgres at ${DATABASE_HOST:-db}:5432"
until pg_isready -h "${DATABASE_HOST:-db}" -p 5432 -U "${DATABASE_USER:-postgres}" >/dev/null 2>&1; do
  sleep 1
done

echo "==> mix ash.setup (create + migrate)"
mix ash.setup

echo "==> mix phx.server"
exec mix phx.server
