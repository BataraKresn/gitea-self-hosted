#!/usr/bin/env bash
# =============================================================================
# check-health.sh – Gitea stack health check script
# Usage: ./check-health.sh
# Exit codes: 0 = all OK, 1 = one or more checks failed
# =============================================================================
set -uo pipefail

COMPOSE_DIR="/opt/gitea"
LOG_FILE="${COMPOSE_DIR}/log/health.log"
DISK_WARN_PCT=80
DISK_CRIT_PCT=90

# shellcheck source=/dev/null
set -a; source "${COMPOSE_DIR}/.env"; set +a

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
PASS() { log "  [PASS] $*"; }
WARN() { log "  [WARN] $*"; WARNINGS=$((WARNINGS+1)); }
FAIL() { log "  [FAIL] $*"; FAILURES=$((FAILURES+1)); }

FAILURES=0
WARNINGS=0

log "========================================"
log " Gitea Health Check"
log "========================================"

# ── 1. Container states ───────────────────────────────────────────────────────
log "[1] Container states"
for SVC in gitea gitea-db gitea-redis gitea-nginx; do
    STATE=$(docker inspect --format='{{.State.Health.Status}}' "${SVC}" 2>/dev/null || echo "not_found")
    STATUS=$(docker inspect --format='{{.State.Status}}' "${SVC}" 2>/dev/null || echo "not_found")
    if [[ "${STATUS}" == "running" && ( "${STATE}" == "healthy" || "${STATE}" == "<no value>" ) ]]; then
        PASS "${SVC}: running"
    elif [[ "${STATUS}" == "running" && "${STATE}" == "starting" ]]; then
        WARN "${SVC}: running but healthcheck still starting"
    else
        FAIL "${SVC}: STATUS=${STATUS} HEALTH=${STATE}"
    fi
done

# ── 2. Gitea HTTP endpoint ────────────────────────────────────────────────────
log "[2] Gitea HTTP health endpoint"
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    --max-time 10 "http://localhost:3000/-/health" 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    PASS "Gitea HTTP /-/health → 200"
else
    FAIL "Gitea HTTP /-/health → ${HTTP_CODE}"
fi

# ── 3. HTTPS via Nginx ────────────────────────────────────────────────────────
log "[3] Nginx HTTPS endpoint"
HTTPS_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -k \
    --max-time 10 "https://localhost/" 2>/dev/null || echo "000")
if [[ "${HTTPS_CODE}" =~ ^(200|301|302)$ ]]; then
    PASS "Nginx HTTPS → ${HTTPS_CODE}"
else
    WARN "Nginx HTTPS → ${HTTPS_CODE} (may be expected if cert not yet placed)"
fi

# ── 4. PostgreSQL connectivity ────────────────────────────────────────────────
log "[4] PostgreSQL connectivity"
PG_OK=$(docker exec gitea-db pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" 2>&1 || echo "failed")
if echo "${PG_OK}" | grep -q "accepting connections"; then
    PASS "PostgreSQL accepting connections"
else
    FAIL "PostgreSQL: ${PG_OK}"
fi

# ── 5. Redis connectivity ─────────────────────────────────────────────────────
log "[5] Redis connectivity"
REDIS_PONG=$(docker exec gitea-redis redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null || echo "failed")
if [[ "${REDIS_PONG}" == "PONG" ]]; then
    PASS "Redis PONG received"
else
    FAIL "Redis: ${REDIS_PONG}"
fi

# ── 6. SSH Git port ───────────────────────────────────────────────────────────
log "[6] SSH Git port ${GITEA_SSH_PORT}"
if nc -z -w5 localhost "${GITEA_SSH_PORT}" 2>/dev/null; then
    PASS "SSH port ${GITEA_SSH_PORT} open"
else
    FAIL "SSH port ${GITEA_SSH_PORT} not reachable"
fi

# ── 7. Disk usage ─────────────────────────────────────────────────────────────
log "[7] Disk usage"
for MOUNT in / "${COMPOSE_DIR}"; do
    if mountpoint -q "${MOUNT}" 2>/dev/null || [[ -d "${MOUNT}" ]]; then
        PCT=$(df "${MOUNT}" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        if [[ "${PCT}" -ge "${DISK_CRIT_PCT}" ]]; then
            FAIL "Disk ${MOUNT}: ${PCT}% used (≥${DISK_CRIT_PCT}%)"
        elif [[ "${PCT}" -ge "${DISK_WARN_PCT}" ]]; then
            WARN "Disk ${MOUNT}: ${PCT}% used (≥${DISK_WARN_PCT}%)"
        else
            PASS "Disk ${MOUNT}: ${PCT}% used"
        fi
    fi
done

# ── 8. Backup freshness ───────────────────────────────────────────────────────
log "[8] Backup freshness (last 25h)"
LATEST_BACKUP=$(find "${COMPOSE_DIR}/backups" -name "gitea_backup_*.tar.gz" \
    -mtime -1 -type f 2>/dev/null | sort | tail -1)
if [[ -n "${LATEST_BACKUP}" ]]; then
    PASS "Latest backup: $(basename "${LATEST_BACKUP}")"
else
    WARN "No backup found in the last 24 hours"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log "========================================"
log " Results: FAIL=${FAILURES}  WARN=${WARNINGS}"
log "========================================"

if [[ "${FAILURES}" -gt 0 ]]; then
    exit 1
fi
exit 0
