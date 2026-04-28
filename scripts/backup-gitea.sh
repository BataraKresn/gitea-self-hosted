#!/usr/bin/env bash
# =============================================================================
# backup-gitea.sh – Production backup for Gitea + PostgreSQL
# Usage:  ./backup-gitea.sh [full|quick]
#   full  – PostgreSQL dump + all Gitea data (default)
#   quick – PostgreSQL dump only (faster, run hourly if needed)
#
# Cron example (daily full backup at 01:00 WIB / UTC+7):
#   0 18 * * * /opt/gitea/scripts/backup-gitea.sh full >> /opt/gitea/log/backup.log 2>&1
# =============================================================================
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
COMPOSE_DIR="/opt/gitea"
BACKUP_DIR="${COMPOSE_DIR}/backups"
LOG_FILE="${COMPOSE_DIR}/log/backup.log"
RETENTION_DAYS=14           # keep backups for N days
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MODE="${1:-full}"

# Load env vars (without exporting shell vars we don't want)
# shellcheck source=/dev/null
set -a; source "${COMPOSE_DIR}/.env"; set +a

BACKUP_NAME="gitea_backup_${MODE}_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ -d "${BACKUP_DIR}" ]] || mkdir -p "${BACKUP_DIR}"
[[ -d "${COMPOSE_DIR}" ]]  || fail "COMPOSE_DIR not found: ${COMPOSE_DIR}"
command -v docker &>/dev/null || fail "docker not found in PATH"

# ── Main ──────────────────────────────────────────────────────────────────────
log "=== Gitea backup started (mode=${MODE}) ==="

mkdir -p "${BACKUP_PATH}"

# ── Step 1: PostgreSQL dump ───────────────────────────────────────────────────
log "Dumping PostgreSQL database '${POSTGRES_DB}'..."
docker exec gitea-db pg_dump \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --format=custom \
    --compress=9 \
    > "${BACKUP_PATH}/gitea_db.pgdump" \
    || fail "pg_dump failed"
log "  → ${BACKUP_PATH}/gitea_db.pgdump ($(du -sh "${BACKUP_PATH}/gitea_db.pgdump" | cut -f1))"

# ── Step 2: Gitea data (full only) ────────────────────────────────────────────
if [[ "${MODE}" == "full" ]]; then
    log "Archiving Gitea data directory..."
    tar \
        --exclude="${COMPOSE_DIR}/gitea-data/gitea/sessions" \
        --exclude="${COMPOSE_DIR}/gitea-data/gitea/tmp" \
        --exclude="${COMPOSE_DIR}/gitea-data/gitea/log" \
        -czf "${BACKUP_PATH}/gitea_data.tar.gz" \
        -C "${COMPOSE_DIR}" \
        gitea-data \
        || fail "tar gitea-data failed"
    log "  → ${BACKUP_PATH}/gitea_data.tar.gz ($(du -sh "${BACKUP_PATH}/gitea_data.tar.gz" | cut -f1))"

    log "Copying app.ini separately for quick reference..."
    cp "${COMPOSE_DIR}/gitea-data/gitea/conf/app.ini" \
       "${BACKUP_PATH}/app.ini.bak"
fi

# ── Step 3: Compress backup folder ───────────────────────────────────────────
log "Compressing backup package..."
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "${BACKUP_DIR}" "${BACKUP_NAME}"
rm -rf "${BACKUP_PATH}"
chmod 600 "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
log "  → ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz ($(du -sh "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1))"

# ── Step 4: Retention policy ──────────────────────────────────────────────────
log "Applying retention policy (keep last ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "gitea_backup_*.tar.gz" \
     -mtime +${RETENTION_DAYS} -delete -print \
     | while read -r f; do log "  Deleted old backup: $f"; done

# ── Step 5: Summary ───────────────────────────────────────────────────────────
TOTAL=$(du -sh "${BACKUP_DIR}" | cut -f1)
log "=== Backup complete. Backup dir total: ${TOTAL} ==="

# ── Optional: sync to S3/MinIO/NAS ───────────────────────────────────────────
# Uncomment and configure as needed:
# aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
#     s3://your-bucket/gitea-backups/ \
#     --storage-class STANDARD_IA
# log "Uploaded to S3: s3://your-bucket/gitea-backups/${BACKUP_NAME}.tar.gz"
