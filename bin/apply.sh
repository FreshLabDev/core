#!/bin/sh
# core-migrate: apply versioned migrations under an advisory lock, then set bot
# role passwords from env. Runs once (compose restart: "no") and exits.
set -eu

: "${PGHOST:=core-postgres}"
: "${PGPORT:=5432}"
: "${PGUSER:=core}"
: "${PGDATABASE:=core}"
export PGPASSWORD="${CORE_POSTGRES_PASSWORD:?CORE_POSTGRES_PASSWORD is required}"

LOCK_KEY=4242424242

echo "core-migrate: waiting for postgres at ${PGHOST}:${PGPORT} ..."
until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; do
  sleep 1
done

# bootstrap schema + migration ledger (idempotent)
psql -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null <<'SQL'
CREATE SCHEMA IF NOT EXISTS core;
CREATE TABLE IF NOT EXISTS core.schema_migrations (
  version    int PRIMARY KEY,
  name       text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

for f in /migrations/*.sql; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  ver=$(printf '%s' "$base" | sed 's/^0*\([0-9][0-9]*\)_.*/\1/')
  case "$ver" in *[!0-9]*|'') echo "core-migrate: skip $base (no numeric version prefix)"; continue;; esac

  applied=$(psql -tAX -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
    -c "SELECT 1 FROM core.schema_migrations WHERE version = $ver")
  if [ "$applied" = "1" ]; then
    echo "core-migrate: skip $base (v$ver already applied)"
    continue
  fi

  echo "core-migrate: applying $base (v$ver) ..."
  # single transaction: advisory lock -> file -> record. Atomic per file.
  psql -v ON_ERROR_STOP=1 --single-transaction \
       -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
       -c "SELECT pg_advisory_xact_lock($LOCK_KEY)" \
       -f "$f" \
       -c "INSERT INTO core.schema_migrations(version, name) VALUES ($ver, '$base')"
  echo "core-migrate: applied $base"
done

# set/rotate bot role passwords from env (roles created LOGIN, unusable until set)
set_pw() {
  role="$1"; pw="$2"
  if [ -z "$pw" ]; then
    echo "core-migrate: WARNING no password for $role (env unset) — role cannot log in yet"
    return
  fi
  esc=$(printf '%s' "$pw" | sed "s/'/''/g")
  psql -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null \
    -c "ALTER ROLE $role WITH LOGIN PASSWORD '$esc'"
  echo "core-migrate: set password for $role"
}
set_pw vido_core    "${VIDO_CORE_PASSWORD:-}"
set_pw searchy_core "${SEARCHY_CORE_PASSWORD:-}"
set_pw quoto_core   "${QUOTO_CORE_PASSWORD:-}"
set_pw branchy_core "${BRANCHY_CORE_PASSWORD:-}"

echo "core-migrate: done."
