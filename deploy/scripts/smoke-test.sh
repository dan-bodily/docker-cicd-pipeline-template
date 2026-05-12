#!/bin/bash
# smoke-test.sh — Post-deploy health validation script
# Triggered by Jenkins after Ansible deploy completes
# Failure here triggers automatic rollback via Jenkinsfile post block
#
# DB ENGINE NOTE: If you change the database engine from PostgreSQL
# update the DB connectivity check below to match your engine:
#   MySQL/MariaDB  → mysqladmin ping -h ${DB_HOST}
#   MSSQL          → /opt/mssql-tools/bin/sqlcmd -S ${DB_HOST} -U ${DB_USER} -P ${DB_PASSWORD} -Q "SELECT 1"
#   Oracle         → sqlplus -S ${DB_USER}/${DB_PASSWORD}@${DB_HOST} <<< "SELECT 1 FROM DUAL;"
# Also update docker-compose.yml, docker-compose.env.template,
# deploy.yml, and rollback.yml

set -e  # Exit immediately on any error — triggers Jenkins failure and rollback

# --- Configuration ---
APP_HOST="${APP_HOST:-localhost}"
APP_PORT="${APP_PORT:-8080}"
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-app}"
MAX_RETRIES=5
RETRY_INTERVAL=10
AUDIT_LOG="/var/log/app/deployments.log"

# --- Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

audit() {
    # Writes to both Jenkins console output and persistent audit log
    # Audit log matches deploy.yml and rollback.yml log format for unified history
    local status=$1
    local message=$2
    log "${message}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${status} | host=$(hostname) | app=${APP_HOST}:${APP_PORT} | db=${DB_HOST}" >> ${AUDIT_LOG}
}

# --- Application Health Check ---
log "Starting smoke test — checking application health endpoint..."

for i in $(seq 1 $MAX_RETRIES); do
    # || echo "000" prevents set -e from exiting on connection failure
    # allowing the retry loop to handle it gracefully
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://${APP_HOST}:${APP_PORT}/health || echo "000")

    if [ "${HTTP_STATUS}" == "200" ]; then
        audit "SMOKE-TEST-APP-PASS" "Application health check passed — HTTP ${HTTP_STATUS}"
        break
    fi

    if [ $i -eq $MAX_RETRIES ]; then
        audit "SMOKE-TEST-APP-FAIL" "ERROR: Application health check failed after ${MAX_RETRIES} attempts — HTTP ${HTTP_STATUS}"
        exit 1
    fi

    log "Attempt ${i}/${MAX_RETRIES} failed — HTTP ${HTTP_STATUS} — retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

# --- Database Connectivity Check ---
# Update this check if switching DB engine (see DB ENGINE NOTE above)
log "Checking database connectivity..."

if pg_isready -h ${DB_HOST} -U ${DB_USER} > /dev/null 2>&1; then
    audit "SMOKE-TEST-DB-PASS" "Database connectivity check passed"
else
    audit "SMOKE-TEST-DB-FAIL" "ERROR: Database connectivity check failed — host=${DB_HOST} user=${DB_USER}"
    exit 1
fi

# --- Container Status Check ---
log "Checking all containers are running..."

UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")
if [ -n "${UNHEALTHY}" ]; then
    audit "SMOKE-TEST-CONTAINER-FAIL" "ERROR: Unhealthy containers detected: ${UNHEALTHY}"
    exit 1
fi

audit "SMOKE-TEST-CONTAINER-PASS" "All containers healthy"

# --- Summary ---
# Full audit trail written to ${AUDIT_LOG}
# Unified log format matches deploy.yml and rollback.yml entries:
#   SMOKE-TEST-APP-PASS / SMOKE-TEST-APP-FAIL
#   SMOKE-TEST-DB-PASS  / SMOKE-TEST-DB-FAIL
#   SMOKE-TEST-CONTAINER-PASS / SMOKE-TEST-CONTAINER-FAIL
audit "SMOKE-TEST-PASS" "Smoke test passed — deployment validated successfully"
exit 0