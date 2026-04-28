# 🚀 Gitea Stack – Quick Reference

**Architecture:** `Client / External Proxy (optional) → Server :80/:443 → Nginx → Gitea :3000 → PostgreSQL + Redis`

---

## 📁 Key Files

| File | Purpose |
|------|---------|
| [docker-compose.yml](/docker-compose.yml) | Single deployment file |
| [nginx/gitea.conf](/nginx/gitea.conf) | Active reverse proxy config |
| [docs/EXTERNAL-REVERSE-PROXY.md](./EXTERNAL-REVERSE-PROXY.md) | External NPM / Cloudflare notes |
| [README.md](/README.md) | Primary documentation |

---

## 🔌 Port Map

| Port | Service | Exposed | Notes |
|------|---------|---------|-------|
| 80 | Nginx | ✅ | Main upstream target for external NPM (recommended) |
| 443 | Nginx | ✅ | HTTPS on this server |
| 2222 | Gitea SSH | ✅ | Git over SSH |
| 3000 | Gitea | ❌ | Internal only |
| 5432 | PostgreSQL | ❌ | Internal only |
| 6379 | Redis | ❌ | Internal only |

---

## 🚀 Core Commands

```bash
# Start stack
docker compose up -d

# Stop stack
docker compose down

# Restart stack
docker compose restart

# Recreate containers
docker compose up -d --force-recreate

# Show status
docker compose ps

# Follow logs
docker compose logs -f
```

---

## 🔍 Verification

### Check container health

```bash
docker compose ps --format "table {{.Names}}\t{{.Status}}"
```

### Check Nginx health endpoint

```bash
curl -I http://SERVER_IP/health-check
```

### Check Gitea from inside Nginx

```bash
docker compose exec nginx wget -qO- http://gitea:3000/-/health | head
```

### Check SSH access

```bash
ssh -T git@SERVER_IP -p 2222
```

---

## 🌐 If Using External NPM

Configure the external NPM server to forward to this server:

- **Scheme:** `http`
- **Forward Hostname / IP:** `SERVER_IP`
- **Forward Port:** `80`
- **Websockets:** enabled
- **Block Common Exploits:** enabled
- **Preserve Host:** enabled

If you want NPM to talk HTTPS upstream instead, use port `443` and ensure this server has a valid certificate.

---

## 🐛 Fast Troubleshooting

### Nginx not starting

```bash
docker compose logs --tail=100 nginx
docker compose exec nginx nginx -t
```

### Gitea unhealthy

```bash
docker compose logs --tail=100 gitea
docker compose exec gitea wget -qO- http://localhost:3000/-/health | head
```

### Database issue

```bash
docker compose logs --tail=100 db
docker compose exec db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

### Redis issue

```bash
docker compose logs --tail=100 redis
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" ping
```

---

## ✅ Production Checklist

- [ ] `.env` filled with strong secrets
- [ ] Ports `80`, `443`, `2222` reachable as intended
- [ ] External NPM/Cloudflare (if any) points to the correct server IP
- [ ] SSL certificates prepared if using local HTTPS
- [ ] `docker compose ps` shows all services healthy
- [ ] SSH clone/push tested
- [ ] Backup routine verified

---

**Last Updated:** April 28, 2026
