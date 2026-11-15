#!/bin/bash
# EmpiFlow kit — create the site, install ERPNext + HR, tighten production flags, add the Metabase read-only user.
# Runs once per fresh volume. Safe to run again: it detects the existing site and only re-applies the settings.
set -euo pipefail

log() { echo "[create-site] $*"; }
die() { echo "[create-site] ERROR: $*" >&2; exit 1; }

: "${SITE_NAME:?SITE_NAME is not set}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD is not set}"
: "${DB_PASSWORD:?DB_PASSWORD is not set}"
RO_PASSWORD="${MB_RO_PASSWORD:-metabase_ro}"
SITE="$SITE_NAME"
# Frappe hashes the database name when the site name contains dots (`_ba376c…`, measured 2026-11-15),
# which breaks the Metabase grant and makes support impossible. Pin it explicitly instead: dots and
# dashes become underscores, so empiflow.local -> empiflow_local.
DB_NAME_DEFAULT="$(echo "$SITE" | tr '.-' '__')"

log "waiting for the database and the two redis instances"
wait-for-it -t 300 -q db:3306 || die "database db:3306 did not open within 300s"
wait-for-it -t 120 -q redis-cache:6379 || die "redis-cache:6379 did not open within 120s"
wait-for-it -t 120 -q redis-queue:6379 || die "redis-queue:6379 did not open within 120s"

log "waiting for the configurator to write sites/common_site_config.json"
for _ in $(seq 1 90); do
    if grep -qs '"db_host"' sites/common_site_config.json \
       && grep -qs '"redis_cache"' sites/common_site_config.json \
       && grep -qs '"redis_queue"' sites/common_site_config.json; then
        break
    fi
    sleep 2
done
grep -qs '"db_host"' sites/common_site_config.json || die "common_site_config.json never got db_host"
log "common_site_config.json is ready"

if [ -f "sites/${SITE}/site_config.json" ]; then
    log "site ${SITE} already exists — not creating it again"
else
    log "creating site ${SITE} (database ${DB_NAME_DEFAULT}) with erpnext + hrms — this takes a few minutes"
    bench new-site \
        --mariadb-user-host-login-scope='%' \
        --db-name="${DB_NAME_DEFAULT}" \
        --admin-password="${ADMIN_PASSWORD}" \
        --db-root-username=root \
        --db-root-password="${DB_PASSWORD}" \
        --install-app erpnext \
        --install-app hrms \
        --set-default \
        "${SITE}"
    log "site ${SITE} created"
fi

# The authoritative database name: whatever Frappe actually recorded for this site.
DB_NAME="$(jq -r '.db_name // empty' "sites/${SITE}/site_config.json")"
[ -n "$DB_NAME" ] || die "could not read db_name from sites/${SITE}/site_config.json"
log "database name: ${DB_NAME}"

log "applying production flags"
bench --site "${SITE}" set-config developer_mode 0
bench --site "${SITE}" set-config enable_scheduler 1
bench --site "${SITE}" set-config pause_scheduler 0

# The BI tool gets SELECT and nothing else (D-006). The password is quoted for SQL by doubling single quotes.
log "ensuring the read-only user metabase_ro on \`${DB_NAME}\`"
ro_sql_password=${RO_PASSWORD//\'/\'\'}
mysql --host=db --user=root --password="${DB_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS 'metabase_ro'@'%' IDENTIFIED BY '${ro_sql_password}';
ALTER USER 'metabase_ro'@'%' IDENTIFIED BY '${ro_sql_password}';
GRANT SELECT ON \`${DB_NAME}\`.* TO 'metabase_ro'@'%';
FLUSH PRIVILEGES;
SQL

bench --site "${SITE}" clear-cache || true

log "DONE — site ${SITE}, database ${DB_NAME}"
