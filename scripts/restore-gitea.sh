#!/usr/bin/env bash
# =============================================================================
# restore-gitea.sh – Restore Gitea from a backup archive
# Usage:  ./restore-gitea.sh /opt/gitea/backups/gitea_backup_full_20260428_010000.tar.gz
#
# WARNING: This will STOP Gitea and OVERWRITE current data.
#          Always run on a tested backup first.
# =============================================================================
set -euo pipefail

COMPOSE_DIR="/opt/gitea"
LOG_FILE="${COMPOSE_DIR}/log/restore.log"

# shellcheck source=/dev/null
set -a; source "${COMPOSE_DIR}/.env"; set +a

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }

# ── Argument check ────────────────────────────────────────────────────────────
BACKUP_ARCHIVE="${1:-}"
[[ -n "${BACKUP_ARCHIVE}" ]] || fail "Usage: $0 <path-to-backup.tar.gz>"
[[ -f "${BACKUP_ARCHIVE}" ]] || fail "Backup archive not found: ${BACKUP_ARCHIVE}"

log "=== Gitea restore started ==="
log "Archive: ${BACKUP_ARCHIVE}"

# ── Step 1: Stop services (keep DB running for restore) ───────────────────────
log "Stopping Gitea and Nginx (DB stays up)..."
cd "${COMPOSE_DIR}"
docker compose stop gitea nginx 2>&1 | tee -a "${LOG_FILE}"

# ── Step 2: Extract archive ───────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
log "Extracting archive to temp dir ${WORK_DIR}..."
tar -xzf "${BACKUP_ARCHIVE}" -C "${WORK_DIR}"
BACKUP_DIR=$(find "${WORK_DIR}" -maxdepth 1 -mindepth 1 -type d | head -1)
[[ -d "${BACKUP_DIR}" ]] || fail "Could not find extracted backup directory"
log "Extracted: ${BACKUP_DIR}"

# ── Step 3: Restore PostgreSQL ────────────────────────────────────────────────
if [[ -f "${BACKUP_DIR}/gitea_db.pgdump" ]]; then
    log "Restoring PostgreSQL database '${POSTGRES_DB}'..."
    # Drop and recreate DB
    docker exec gitea-db psql -U "${POSTGRES_USER}" -c \
        "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"
    docker exec gitea-db psql -U "${POSTGRES_USER}" -c \
        "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};" 2>&1 | tee -a "${LOG_FILE}"
    # Restore dump
    docker exec -i gitea-db pg_restore \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --no-owner \
        --role="${POSTGRES_USER}" \
        < "${BACKUP_DIR}/gitea_db.pgdump" 2>&1 | tee -a "${LOG_FILE}" || true
    log "  → Database restored."
else
    log "  WARNING: No DB dump found in archive. Skipping database restore."
fi

# ── Step 4: Restore Gitea data ────────────────────────────────────────────────
if [[ -f "${BACKUP_DIR}/gitea_data.tar.gz" ]]; then
    log "Restoring Gitea data directory..."
    # Backup current data just in case
    CURRENT_BACKUP="${COMPOSE_DIR}/gitea-data.pre-restore.$(date +%Y%m%d_%H%M%S)"
    log "  Moving current gitea-data to ${CURRENT_BACKUP}"
    mv "${COMPOSE_DIR}/gitea-data" "${CURRENT_BACKUP}"
    # Extract new data
    tar -xzf "${BACKUP_DIR}/gitea_data.tar.gz" -C "${COMPOSE_DIR}"
    log "  → Gitea data restored."
else
    log "  INFO: No gitea_data.tar.gz found. Skipping data restore (DB-only restore)."
fi

# ── Step 5: Fix permissions ───────────────────────────────────────────────────
log "Fixing ownership on gitea-data (UID/GID 1000)..."
docker run --rm \
    -v "${COMPOSE_DIR}/gitea-data:/data" \
    busybox chown -R 1000:1000 /data 2>&1 | tee -a "${LOG_FILE}"

# ── Step 6: Start services ────────────────────────────────────────────────────
log "Starting all services..."
cd "${COMPOSE_DIR}"
docker compose up -d 2>&1 | tee -a "${LOG_FILE}"

# ── Step 7: Verify ────────────────────────────────────────────────────────────
log "Waiting 30s for services to stabilise..."
sleep 30

log "Checking service health..."
docker compose ps 2>&1 | tee -a "${LOG_FILE}"

HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    --max-time 15 \
    "http://localhost:3000/-/health" 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    log "  → Gitea health check: OK (HTTP ${HTTP_CODE})"
else
    log "  WARNING: Gitea health check returned HTTP ${HTTP_CODE}. Check logs."
    log "  Run: docker compose logs --tail=50 gitea"
fi

log "=== Restore complete ==="
log ""
log "Post-restore verification checklist:"
log "  1. docker compose ps                           – all services running"
log "  2. curl -I https://git.company.id/             – HTTPS accessible"
log "  3. ssh -p 2222 git@git.company.id              – SSH banner returned"
log "  4. git clone <a repo> and verify contents"
log "  5. Login to web UI, check repositories and users"
log "  6. Verify LFS objects accessible"
