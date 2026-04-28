#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

log()  { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*"; }

get_env_value() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" .env | tail -n1 || true)"
  printf '%s' "${line#*=}"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="${value//&/\\&}"

  if grep -qE "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${escaped}|" .env
  else
    printf '\n%s=%s\n' "$key" "$value" >> .env
  fi
}

is_placeholder_or_empty() {
  local value="$1"
  [[ -z "$value" ]] && return 0
  [[ "$value" == REPLACE_WITH_* ]] && return 0
  [[ "$value" == \"REPLACE_WITH_* ]] && return 0
  return 1
}

generate_b64() {
  local bytes="$1"
  openssl rand -base64 "$bytes" | tr -d '\n'
}

ensure_env_secrets() {
  local generated_any=0

  # key|openssl_bytes
  local specs=(
    "GITEA_SECRET_KEY|48"
    "GITEA_INTERNAL_TOKEN|64"
    "GITEA_JWT_SECRET|32"
    "GITEA_LFS_JWT_SECRET|32"
    "POSTGRES_PASSWORD|24"
    "REDIS_PASSWORD|24"
  )

  for spec in "${specs[@]}"; do
    local key bytes current new_value
    key="${spec%%|*}"
    bytes="${spec##*|}"
    current="$(get_env_value "$key")"

    if is_placeholder_or_empty "$current"; then
      require_cmd openssl
      new_value="$(generate_b64 "$bytes")"
      set_env_value "$key" "$new_value"
      generated_any=1
      log "Generated secret for: $key"
    else
      log "Keep existing secret: $key"
    fi
  done

  if [[ "$generated_any" -eq 1 ]]; then
    warn "Some secrets/passwords were auto-generated and written to .env"
  fi
}

ensure_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    log "Skip (exists): $dir"
  else
    mkdir -p "$dir"
    log "Created: $dir"
  fi
}

wait_for_healthy() {
  local timeout_sec="${1:-180}"
  local interval_sec=3
  local start_ts now_ts elapsed
  start_ts="$(date +%s)"

  log "Waiting for services to become healthy (timeout: ${timeout_sec}s)..."

  while true; do
    local all_ok=1
    local services
    services="$(docker compose ps --services)"

    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue

      local cid status
      cid="$(docker compose ps -q "$svc")"
      if [[ -z "$cid" ]]; then
        all_ok=0
        warn "Service '$svc' has no running container yet"
        continue
      fi

      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
      case "$status" in
        healthy|running)
          ;;
        *)
          all_ok=0
          warn "Service '$svc' status: $status"
          ;;
      esac
    done <<< "$services"

    if [[ "$all_ok" -eq 1 ]]; then
      log "All services are healthy ✅"
      return 0
    fi

    now_ts="$(date +%s)"
    elapsed="$((now_ts - start_ts))"
    if [[ "$elapsed" -ge "$timeout_sec" ]]; then
      err "Health check timeout after ${timeout_sec}s"
      docker compose ps || true
      return 1
    fi

    sleep "$interval_sec"
  done
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Command '$1' not found. Please install it first."
    exit 1
  fi
}

log "Checking prerequisites..."
require_cmd docker
if ! docker compose version >/dev/null 2>&1; then
  err "Docker Compose plugin is not available (docker compose)."
  exit 1
fi

if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    warn "File .env not found, creating from .env.example"
    cp .env.example .env
    warn "Created .env from template; secrets/passwords will be auto-filled if placeholders are found."
  else
    err "File .env and .env.example are both missing."
    exit 1
  fi
fi

log "Ensuring .env secrets/passwords are set..."
ensure_env_secrets

log "Ensuring runtime directories (.gitignore paths)..."
ensure_dir "postgres-data"
ensure_dir "postgres-data/pgdata"
ensure_dir "gitea-data"
ensure_dir "log"
ensure_dir "log/nginx"
ensure_dir "backups"
ensure_dir "ssl"

# Optional helper marker to keep empty dirs visible in some tooling
for d in backups log log/nginx ssl gitea-data postgres-data postgres-data/pgdata; do
  touch "$d/.gitkeep" || true
done

# Ensure TLS files expected by nginx/gitea.conf exist.
# If missing, generate a self-signed cert so stack can start in one run.
CERT_FILE="ssl/_mugshot_dev.pem"
KEY_FILE="ssl/_mugshot_dev.key"

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  warn "TLS cert/key not found ($CERT_FILE, $KEY_FILE). Generating self-signed certificate..."
  require_cmd openssl

  DOMAIN="$(grep -E '^GITEA_DOMAIN=' .env | head -n1 | cut -d'=' -f2- | tr -d '"' || true)"
  DOMAIN="${DOMAIN:-localhost}"

  openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 365 \
    -subj "/CN=${DOMAIN}" >/dev/null 2>&1

  warn "Generated self-signed cert for CN=${DOMAIN}. Replace with trusted cert in production."
fi

log "Validating docker compose configuration..."
docker compose config >/dev/null

log "Starting stack..."
docker compose up -d

wait_for_healthy 180

log "Current container status:"
docker compose ps

log "Deployment done ✅"
log "Web:  http://<server-ip>"
log "HTTPS: https://<server-ip>"
log "SSH:  ssh git@<server-ip> -p 2222"
