# External Reverse Proxy Guide

This stack is designed to run on **one application server** with the following containers:

- `nginx`
- `gitea`
- `db`
- `redis`

If you use **Cloudflare**, **Nginx Proxy Manager (NPM)**, or another reverse proxy on a **different server**, that external layer should forward traffic to this server.

---

## Recommended Request Flow

```text
Client
  ↓
Cloudflare (optional)
  ↓
NPM / external reverse proxy (optional)
  ↓
This server :80 or :443
  ↓
Nginx container
  ↓
Gitea :3000
```

---

## Recommended NPM Settings

Use these values in the external NPM instance:

- **Domain Names:** your Gitea domain, for example `git.example.com`
- **Scheme:** `http`
- **Forward Hostname / IP:** public IP or private IP of this server
- **Forward Port:** `80`
- **Cache Assets:** optional
- **Block Common Exploits:** enabled
- **Websockets Support:** enabled

### When to use port 443 instead

Use `443` only if:

- this server also terminates TLS, and
- the certificate on this server is valid for the same hostname

If NPM already handles TLS, forwarding to port `80` is usually simpler.

---

## Firewall Guidance

Open these ports on the application server:

- `80/tcp`
- `443/tcp`
- `2222/tcp`

If possible, restrict `80` and `443` so only the external proxy server can access them.

---

## Gitea Environment Notes

Make sure `.env` is consistent with the public URL used by the proxy:

```env
GITEA_DOMAIN=git.example.com
GITEA_ROOT_URL=https://git.example.com/
GITEA_SSH_DOMAIN=git.example.com
GITEA_SSH_PORT=2222
```

Even if NPM is on another server, `GITEA_ROOT_URL` should still use the final public URL seen by users.

---

## Verification

### From the application server

```bash
curl -I http://127.0.0.1/health-check
curl -I http://SERVER_IP/health-check
ssh -T git@SERVER_IP -p 2222
```

### From the proxy server

```bash
curl -I http://APP_SERVER_IP/health-check
curl -I http://APP_SERVER_IP/
```

### From the client side

```bash
curl -I https://git.example.com/
ssh -T git@git.example.com -p 2222
```

---

## Common Pitfalls

### Wrong upstream port

Do **not** point external NPM to Gitea port `3000` directly unless you intentionally want to bypass Nginx.

Recommended upstreams:

- `SERVER_IP:80`
- `SERVER_IP:443`

### Root URL mismatch

If Gitea redirects to the wrong host or protocol, check:

- `GITEA_DOMAIN`
- `GITEA_ROOT_URL`
- `GITEA_SSH_DOMAIN`

### SSL confusion

Choose one of these clearly:

1. **TLS at NPM only** → NPM forwards to `http://SERVER_IP:80`
2. **TLS at NPM and app server** → NPM forwards to `https://SERVER_IP:443`

Avoid “half-configured TLS” on both sides unless you really need it.

---

## Summary

This repository runs the **application stack only**. External proxy layers are welcome, but they should treat this server as a normal upstream and forward traffic to Nginx on port `80` or `443`.
