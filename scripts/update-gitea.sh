#!/usr/bin/env bash
# =============================================================================
# update-gitea.sh – Safe Gitea upgrade procedure
# Usage:  ./update-gitea.sh <new-version>
# Example: ./update-gitea.sh 1.23.2
#
# Procedure:
#   1. Validate arguments
#   2. Run backup (full)
#   3. Update image tag in docker-compose.yml
#   4. Pull new image
#   5. Recreate Gitea container
#   6. Health check
#   7. Rollback if unhealthy
# =============================================================================
set -euo pipefail

COMPOSE_DIR="/opt/gitea"
LOG_FILE="${COMPOSE_DIR}/log/update.log"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"

# shellcheck source=/dev/null
set -a; source "${COMPOSE_DIR}/.env"; set +a

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }

# ── Argument ──────────────────────────────────────────────────────────────────
NEW_VERSION="${1:-}"
[[ -n "${NEW_VERSION}" ]] || fail "Usage: $0 <gitea-version>  e.g. $0 1.23.2"
# Strip leading 'v' if present
NEW_VERSION="${NEW_VERSION#v}"

CURRENT_VERSION=$(grep 'image: gitea/gitea:' "${COMPOSE_FILE}" | head -1 | sed 's/.*gitea\/gitea://' | tr -d ' ')
log "=== Gitea upgrade started: ${CURRENT_VERSION} → ${NEW_VERSION} ==="

# ── Step 1: Pre-upgrade backup ────────────────────────────────────────────────
log "Running pre-upgrade full backup..."
bash "${COMPOSE_DIR}/scripts/backup-gitea.sh" full 2>&1 | tee -a "${LOG_FILE}"

# ── Step 2: Update image tag in docker-compose.yml ────────────────────────────
log "Pinning new version in docker-compose.yml..."
sed -i "s|image: gitea/gitea:${CURRENT_VERSION}|image: gitea/gitea:${NEW_VERSION}|g" \
    "${COMPOSE_FILE}"
log "  → Updated to gitea/gitea:${NEW_VERSION}"

# ── Step 3: Pull new image ────────────────────────────────────────────────────
log "Pulling gitea/gitea:${NEW_VERSION}..."
cd "${COMPOSE_DIR}"
docker compose pull gitea 2>&1 | tee -a "${LOG_FILE}"

# ── Step 4: Recreate Gitea container ─────────────────────────────────────────
log "Recreating Gitea container..."
docker compose up -d --no-deps gitea 2>&1 | tee -a "${LOG_FILE}"

# ── Step 5: Health check ──────────────────────────────────────────────────────
log "Waiting 60s for Gitea to start..."
sleep 60

HEALTHY=false
for i in {1..6}; do
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
        --max-time 10 "http://localhost:3000/-/health" 2>/dev/null || echo "000")
    if [[ "${HTTP_CODE}" == "200" ]]; then
        HEALTHY=true
        log "  → Health check passed (attempt ${i}, HTTP ${HTTP_CODE})"
        break
    fi
    log "  → Health check attempt ${i}: HTTP ${HTTP_CODE} – waiting 15s..."
    sleep 15
done

# ── Step 6: Rollback if unhealthy ─────────────────────────────────────────────
if [[ "${HEALTHY}" == "false" ]]; then
    log "=== HEALTH CHECK FAILED – Rolling back to ${CURRENT_VERSION} ==="
    sed -i "s|image: gitea/gitea:${NEW_VERSION}|image: gitea/gitea:${CURRENT_VERSION}|g" \
        "${COMPOSE_FILE}"
    docker compose up -d --no-deps gitea 2>&1 | tee -a "${LOG_FILE}"
    log "Rolled back to gitea/gitea:${CURRENT_VERSION}."
    log "Check logs: docker compose logs --tail=100 gitea"
    exit 1
fi

log "=== Upgrade complete: gitea/gitea:${NEW_VERSION} is running ==="
docker compose ps 2>&1 | tee -a "${LOG_FILE}"

# ── Tip ───────────────────────────────────────────────────────────────────────
log ""
log "Post-upgrade checklist:"
log "  1. Confirm web UI accessible at ROOT_URL"
log "  2. git clone a repository and verify"
log "  3. Check Admin → Dashboard → Run all cron tasks"
log "  4. Monitor logs for 30 min: docker compose logs -f gitea"
