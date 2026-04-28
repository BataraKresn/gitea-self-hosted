# 🐙 Gitea Stack – Production-Ready Docker Deployment

[![GitHub License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2.0%2B-blue)](https://docs.docker.com/compose/)
[![Gitea Version](https://img.shields.io/badge/Gitea-1.23.1-blue)](https://gitea.io)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16.3-blue)](https://www.postgresql.org/)
[![Nginx](https://img.shields.io/badge/Nginx-1.27-blue)](https://nginx.org/)

**Self-hosted Git server** – Complete production-ready deployment for Gitea using Docker Compose with PostgreSQL, Redis, and Nginx reverse proxy.

---

## 📋 Quick Links

- **[📚 Documentation](docs/)** – Complete guides and references
- **[⚡ Quick Start](#-quick-start)** – Get running in 5 minutes
- **[🏗️ Architecture](#-architecture)** – System design
- **[🔧 Commands](#-common-commands)** – Helpful commands

---

## 🚀 Quick Start

```bash
# 1. Clone repository
git clone https://github.com/your-org/gitea-stack.git /opt/gitea
cd /opt/gitea

# 2. Setup environment
cp .env.example .env
nano .env  # Edit domain & passwords

# 3. Start services
docker compose up -d
docker compose ps

# 4. Access Gitea
# Web: http://localhost:3000
# SSH: ssh git@localhost -p 2222
```

---

## 🏗️ Architecture

### Component Diagram

```
┌─────────────────────────────────────┐
│  Client: Browser / Git              │
└──────────────┬──────────────────────┘
               │
        ┌──────▼──────────┐
        │  Nginx Proxy    │ Ports: 80, 443, 2222
        │  Container      │
        └──────┬──────────┘
               │ Internal Network
    ┌──────────┼──────────┬─────────┐
    │          │          │         │
 ┌──▼──┐  ┌────▼─────┐  ┌─▼────┐  │
 │Gitea│  │PostgreSQL│  │Redis │  │
 │ App │  │Database  │  │Cache │  │
 └─────┘  └──────────┘  └──────┘  │
```

### Port Mapping

| Port | Service | Purpose | Exposed |
|------|---------|---------|---------|
| **80** | Nginx | HTTP → HTTPS redirect | ✅ Yes |
| **443** | Nginx | HTTPS web UI & Git | ✅ Yes |
| **2222** | Gitea | Git SSH (clone/push) | ✅ Yes |
| 3000 | Gitea | Internal HTTP only | ❌ No |
| 5432 | PostgreSQL | Internal only | ❌ No |
| 6379 | Redis | Internal only | ❌ No |

### Advanced: Three-Layer Proxy

For Cloudflare + NPM setup, see [Cloudflare + NPM Flow](docs/cloudflare-npm-flow.md):

```
Internet → Cloudflare → NPM (:80,443) → Nginx (:8080) → Gitea (:3000)
```

---

## 📚 Documentation

### Getting Started

- **[QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md)** – Cheat sheet with common commands
- **[npm-setup-guide.md](docs/npm-setup-guide.md)** – Setup Nginx Proxy Manager
- **[backup-restore.md](docs/backup-restore.md)** – Backup & disaster recovery

### Advanced

- **[cloudflare-npm-flow.md](docs/cloudflare-npm-flow.md)** – Three-layer proxy architecture
- **[topology-npm-architecture.md](docs/topology-npm-architecture.md)** – Visual diagrams
- **[troubleshooting.md](docs/troubleshooting.md)** – Common issues & solutions

---

## 📦 Installation

### Prerequisites

- **Docker** 20.10+
- **Docker Compose** 2.0+
- **2GB+ RAM** (4GB+ recommended)
- **10GB+ disk** space
- Ports available: **80, 443, 2222**

### Step 1: Clone & Setup

```bash
git clone https://github.com/your-org/gitea-stack.git /opt/gitea
cd /opt/gitea
cp .env.example .env
```

### Step 2: Generate Secrets

```bash
# Generate strong random values
GITEA_SECRET_KEY=$(openssl rand -base64 48)
GITEA_INTERNAL_TOKEN=$(openssl rand -base64 64 | tr -d '\n')
GITEA_JWT_SECRET=$(openssl rand -base64 48)
POSTGRES_PASSWORD=$(openssl rand -base64 24)
REDIS_PASSWORD=$(openssl rand -base64 24)

# Copy output and paste into .env file
```

### Step 3: Configure Domain

Edit `.env`:

```env
GITEA_DOMAIN=git.example.com
GITEA_ROOT_URL=https://git.example.com/
GITEA_SSH_DOMAIN=git.example.com
GITEA_SSH_PORT=2222

# Paste secrets from Step 2
GITEA_SECRET_KEY=<paste-here>
GITEA_INTERNAL_TOKEN=<paste-here>
GITEA_JWT_SECRET=<paste-here>
POSTGRES_PASSWORD=<paste-here>
REDIS_PASSWORD=<paste-here>
```

### Step 4: Setup SSL Certificates

```bash
# Option A: Let's Encrypt (Recommended)
sudo certbot certonly --standalone -d git.example.com
sudo cp /etc/letsencrypt/live/git.example.com/fullchain.pem ./ssl/
sudo cp /etc/letsencrypt/live/git.example.com/privkey.pem ./ssl/
sudo chown $(id -u):$(id -g) ./ssl/*

# Option B: Self-signed (Development only)
openssl req -x509 -newkey rsa:4096 -keyout ./ssl/privkey.pem -out ./ssl/fullchain.pem -days 365 -nodes
```

### Step 5: Start Services

```bash
docker compose up -d
docker compose ps         # Verify all services running
docker compose logs -f    # Watch startup logs
```

Access Gitea: **http://localhost:3000**

---

## ⚙️ Configuration

### Key Environment Variables

```env
# Server
GITEA_DOMAIN=git.example.com
GITEA_ROOT_URL=https://git.example.com/
GITEA_SSH_DOMAIN=git.example.com
GITEA_SSH_PORT=2222
GITEA_SSH_BIND_IP=0.0.0.0

# Database
POSTGRES_DB=gitea
POSTGRES_USER=gitea
POSTGRES_PASSWORD=<password>

# Redis
REDIS_PASSWORD=<password>

# Security
GITEA_DISABLE_REGISTRATION=true
GITEA_REVERSE_PROXY_LIMIT=1
GITEA_TRUSTED_PROXIES=127.0.0.1/8

# Timezone
TZ=Asia/Jakarta
```

See [Gitea Config Docs](https://docs.gitea.io/en-us/config-cheat-sheet/) for all options.

---

## 🔧 Common Commands

### Service Management

```bash
# Start/stop/restart
docker compose up -d                          # Start all services
docker compose down                           # Stop all services
docker compose restart                        # Restart all services
docker compose restart gitea                  # Restart specific service
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service (last 50 lines)
docker compose logs -f --tail=50 gitea
docker compose logs -f --tail=50 nginx
docker compose logs -f --tail=50 db

# Filter by keyword
docker compose logs gitea | grep ERROR
```

### Status & Health

```bash
# Container status
docker compose ps

# Health check
docker compose ps --format "table {{.Names}}\t{{.Status}}"

# Resource usage
docker stats

# Database size
docker compose exec db psql -U gitea gitea -c "SELECT pg_size_pretty(pg_database_size(current_database()));"
```

### Container Access

```bash
# SSH into Gitea
docker compose exec gitea sh

# PostgreSQL shell
docker compose exec db psql -U gitea gitea

# Redis CLI
docker compose exec redis redis-cli -a "$REDIS_PASSWORD"
```

### Backup & Restore

```bash
# Full backup
docker compose exec db pg_dump -U gitea gitea > backup.sql

# Restore
docker compose exec -T db psql -U gitea gitea < backup.sql

# See backup guide for automated backups
# docs/backup-restore.md
```

---

## 🔐 Security

### Best Practices

1. **Change all default passwords** – Edit `.env`
2. **Enable HTTPS** – Place SSL certificates in `./ssl/`
3. **Disable registration** – Set `GITEA_DISABLE_REGISTRATION=true`
4. **Strong admin password** – Create in Gitea UI
5. **Restrict SSH access** – Use firewall rules
6. **Regular backups** – Automate backup schedule
7. **Keep updated** – Update container images regularly
8. **Monitor logs** – Watch for suspicious activity

### Firewall Rules (UFW)

```bash
# Allow web traffic
ufw allow 80/tcp
ufw allow 443/tcp

# Allow Git SSH
ufw allow 2222/tcp

# Allow admin SSH (restrict to known IPs)
ufw allow from 10.0.0.0/8 to any port 22
ufw allow from YOUR_IP to any port 22

ufw enable
```

---

## 💾 Backup & Restore

### Quick Backup

```bash
# PostgreSQL dump
docker compose exec db pg_dump -U gitea gitea | gzip > backup-$(date +%Y%m%d).sql.gz

# Gitea data volume
tar czf gitea-data-$(date +%Y%m%d).tar.gz ./gitea-data/
```

### Automated Backups

Add to crontab (`crontab -e`):

```bash
# Daily backup at 2 AM
0 2 * * * cd /opt/gitea && docker compose exec db pg_dump -U gitea gitea | gzip > backups/db-$(date +\%Y\%m\%d).sql.gz

# Keep 7 days of backups
0 3 * * * find /opt/gitea/backups -name "db-*" -mtime +7 -delete
```

See [Backup & Restore Guide](docs/backup-restore.md) for detailed procedures.

---

## 🚨 Troubleshooting

### Services Not Starting

```bash
# View detailed logs
docker compose logs -f

# Restart with verbose output
docker compose down
docker compose up

# Check if ports are in use
netstat -tuln | grep -E ':(80|443|2222)'
```

### Database Connection Error

```bash
# Verify PostgreSQL is running
docker compose ps db

# Check database logs
docker compose logs db

# Verify credentials
grep POSTGRES_ .env
```

### Git SSH Not Working

```bash
# Test SSH connection
ssh -vvv git@localhost -p 2222

# Check Gitea logs for SSH errors
docker compose logs gitea | grep -i ssh

# Verify port is exposed
netstat -tuln | grep 2222
```

See [Troubleshooting Guide](docs/troubleshooting.md) for more solutions.

---

## 📊 Monitoring

### Container Status

```bash
watch docker compose ps
```

### Logs Monitoring

```bash
# Real-time all logs
docker compose logs -f

# Specific service
docker compose logs -f --tail=100 gitea
```

### Disk Usage

```bash
# Total usage
du -sh .

# Per-component
du -sh ./gitea-data ./postgres-data ./backups

# Database size
docker compose exec db psql -U gitea gitea -c "SELECT pg_size_pretty(pg_database_size('gitea'));"
```

---

## 🚀 Deployment Options

### Option 1: Standard (Recommended)

Simple single-server deployment:

```bash
docker compose up -d
```

### Option 2: With NPM

Multi-app support with centralized SSL:

See [NPM Setup Guide](docs/npm-setup-guide.md)

### Option 3: With Cloudflare + NPM

Enterprise setup with DDoS protection:

See [Cloudflare + NPM Flow](docs/cloudflare-npm-flow.md)

---

## 📁 Project Structure

```
/opt/gitea/
├── docker-compose.yml              ← Main config
├── docker-compose-npm.yml          ← NPM config (optional)
├── .env                            ← Secrets (NEVER commit)
├── .env.example                    ← Template
├── .gitignore                      ← Git ignore rules
│
├── nginx/                          ← Nginx configs
│   ├── gitea.conf
│   ├── gitea-npm.conf
│   └── proxy_params.inc
│
├── ssl/                            ← SSL certificates
│   ├── fullchain.pem
│   └── privkey.pem
│
├── gitea-data/                     ← Gitea data (volume)
├── postgres-data/                  ← Database data (volume)
├── log/                            ← Container logs
│   └── nginx/
│
├── docs/                           ← Documentation
│   ├── QUICK-REFERENCE.md
│   ├── npm-setup-guide.md
│   ├── cloudflare-npm-flow.md
│   ├── topology-npm-architecture.md
│   ├── backup-restore.md
│   └── troubleshooting.md
│
└── backups/                        ← Backup files
```

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -am 'Add improvement'`)
4. Push to branch (`git push origin feature/improvement`)
5. Create Pull Request

---

## 📝 License

Licensed under the MIT License – see [LICENSE](LICENSE) for details.

---

## 🆘 Support

### Documentation

- [Gitea Docs](https://docs.gitea.io/)
- [Docker Docs](https://docs.docker.com/)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)
- [Nginx Docs](https://nginx.org/en/docs/)

### Getting Help

- **Issues:** [GitHub Issues](https://github.com/your-org/gitea-stack/issues)
- **Discussions:** [GitHub Discussions](https://github.com/your-org/gitea-stack/discussions)
- **Gitea Community:** [gitea.community](https://gitea.community/)

### Reporting Security Issues

Please email **security@your-domain.com** instead of using the issue tracker.

---

## 📌 Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes.

---

**Version:** 1.0.0  
**Last Updated:** April 28, 2026  
**Maintained by:** Your Team
