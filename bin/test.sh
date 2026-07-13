#!/bin/sh
# Run every migration and SQL contract check in a disposable PostgreSQL 17
# container. Nothing is published to the host and the container is always
# removed on exit.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CONTAINER="core-contract-test-$$-$(date +%s)"
OWNER_PASSWORD="core-test-owner"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --detach --rm \
  --name "$CONTAINER" \
  --tmpfs /var/lib/postgresql/data \
  -e POSTGRES_USER=core \
  -e POSTGRES_PASSWORD="$OWNER_PASSWORD" \
  -e POSTGRES_DB=core \
  postgres:17-alpine >/dev/null

attempt=0
until docker exec "$CONTAINER" pg_isready -U core -d core >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    echo "core-test: PostgreSQL did not become ready" >&2
    docker logs "$CONTAINER" >&2 || true
    exit 1
  fi
  sleep 1
done

docker exec "$CONTAINER" mkdir -p /migrations
docker cp "$ROOT/migrations/." "$CONTAINER:/migrations/" >/dev/null
docker cp "$ROOT/bin/apply.sh" "$CONTAINER:/apply.sh" >/dev/null

run_migrations() {
  docker exec \
    -e PGHOST=/var/run/postgresql \
    -e PGPORT=5432 \
    -e PGUSER=core \
    -e PGDATABASE=core \
    -e CORE_POSTGRES_PASSWORD="$OWNER_PASSWORD" \
    -e VIDO_CORE_PASSWORD=core-test-vido \
    -e SEARCHY_CORE_PASSWORD=core-test-searchy \
    -e QUOTO_CORE_PASSWORD=core-test-quoto \
    -e BRANCHY_CORE_PASSWORD=core-test-branchy \
    -e MAKEITMD_CORE_PASSWORD=core-test-makeitmd \
    "$CONTAINER" /bin/sh /apply.sh
}

echo "core-test: clean install"
run_migrations

echo "core-test: idempotent second run"
run_migrations

applied=$(docker exec "$CONTAINER" \
  psql -tAX -v ON_ERROR_STOP=1 -U core -d core \
  -c "SELECT count(*) FROM core.schema_migrations")
expected=$(find "$ROOT/migrations" -maxdepth 1 -type f -name '[0-9][0-9][0-9]_*.sql' | wc -l | tr -d ' ')
if [ "$applied" != "$expected" ]; then
  echo "core-test: expected $expected applied migrations, found $applied" >&2
  exit 1
fi

for test_file in "$ROOT"/tests/*.sql; do
  [ -e "$test_file" ] || continue
  echo "core-test: $(basename "$test_file")"
  docker exec -i "$CONTAINER" \
    psql -v ON_ERROR_STOP=1 -U core -d core <"$test_file"
done

echo "core-test: all checks passed"
