#!/usr/bin/env bash
# Applies the Supabase stub, every migration and every test file to a
# throwaway Postgres, stopping at the first error.
#
#   supabase/ci-tests/run.sh              # uses $DATABASE_URL, else docker postgres:16
set -euo pipefail
cd "$(dirname "$0")/.."

run_sql() {
  local url="$1"
  for f in ci-tests/00_supabase_stub.sql migrations/*.sql ci-tests/[1-9]*.sql; do
    echo "── $f"
    psql "$url" -v ON_ERROR_STOP=1 -q -X -f "$f"
  done
}

if [[ -n "${DATABASE_URL:-}" ]]; then
  run_sql "$DATABASE_URL"
  exit 0
fi

name="pickleball-sql-$$"
docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test -v "$PWD:/supabase:ro" postgres:16 >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 60); do
  docker exec "$name" pg_isready -U postgres -q && break
  sleep 0.5
done
sleep 1
docker exec -w /supabase "$name" bash -c '
  set -euo pipefail
  for f in ci-tests/00_supabase_stub.sql migrations/*.sql ci-tests/[1-9]*.sql; do
    echo "── $f"
    psql -U postgres -v ON_ERROR_STOP=1 -q -X -f "$f"
  done'
