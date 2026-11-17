#!/bin/bash
# Provisions one role + database per app sharing this Postgres instance.
#
# Postgres only runs files in /docker-entrypoint-initdb.d on a brand-new,
# empty data volume (first-ever container start). If postgres-data already
# has data, this will NOT run automatically — apply it by hand instead:
#
#   docker compose exec -T postgres bash < init/10-app-databases.sh
#
# (or copy/paste the SQL block below into `docker compose exec postgres
# psql -U postgres`). It's idempotent — safe to re-run.
#
# Passwords default to the app name for convenience, matching this repo's
# ${VAR:-default} convention; override via the same-named env var passed to
# the postgres service before first boot, or after the fact with
# `ALTER ROLE <app> WITH PASSWORD '...'`.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'paperclip') THEN
      CREATE ROLE paperclip WITH LOGIN PASSWORD '${PAPERCLIP_DB_PASSWORD:-paperclip}';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'hindsight') THEN
      CREATE ROLE hindsight WITH LOGIN PASSWORD '${HINDSIGHT_DB_PASSWORD:-hindsight}';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'privatebin') THEN
      CREATE ROLE privatebin WITH LOGIN PASSWORD '${PRIVATEBIN_DB_PASSWORD:-privatebin}';
    END IF;
  END
  \$\$;
EOSQL

for db in paperclip hindsight privatebin; do
  exists=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '${db}'")
  if [ "$exists" != "1" ]; then
    createdb --username "$POSTGRES_USER" --owner "$db" "$db"
  fi
done

# hindsight needs pgvector available in its own database specifically.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname hindsight \
  -c 'CREATE EXTENSION IF NOT EXISTS vector;'
