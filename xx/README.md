# nginx Proxy Management System

A flexible system for managing nginx reverse proxy configurations with easy domain addition and port forwarding.

## Quick Start

```bash
# 1. Setup nginx proxy system
./setup-nginx.sh

# 2. Add your first domain
./add-domain.sh --domain version-01.abc.com --toPort 3000

# 3. Check status
./list-domains.sh
```

## Scripts Overview

| Script | Purpose | Example Usage |
|--------|---------|---------------|
| `setup-nginx.sh` | Initial nginx setup | `./setup-nginx.sh` |
| `add-domain.sh` | Add domain proxy | `./add-domain.sh --domain example.com --toPort 3000` |
| `remove-domain.sh` | Remove domain proxy | `./remove-domain.sh --domain example.com` |
| `list-domains.sh` | List all domains | `./list-domains.sh` |
| `nginx-status.sh` | Show nginx status | `./nginx-status.sh` |

## add-domain.sh Options

```bash
./add-domain.sh --domain DOMAIN --toPort PORT [OPTIONS]

Required:
  --domain DOMAIN     Domain name (e.g., version-01.abc.com)
  --toPort PORT       Target port (e.g., 3000)

Optional:
  --fromPort PORT     Source port (default: 80)
  --ssl               Enable SSL/HTTPS setup
  --rate-limit ZONE   Rate limiting: web|api (default: web)
```

## Examples

```bash
# Basic Rails app
./add-domain.sh --domain version-01.abc.com --toPort 3000

# API with SSL and API rate limiting
./add-domain.sh --domain api.abc.com --toPort 4000 --ssl --rate-limit api

# Custom port mapping
./add-domain.sh --domain dev.abc.com --toPort 8080 --fromPort 8000

# Multiple Rails versions
./add-domain.sh --domain v1.abc.com --toPort 3001
./add-domain.sh --domain v2.abc.com --toPort 3002
./add-domain.sh --domain v3.abc.com --toPort 3003
```

## Monitoring

- Status page: http://localhost:8080/status
- Domain list: http://localhost:8080/domains
- Health check: http://YOUR-DOMAIN/nginx-health
- Logs: `/var/log/nginx/proxy/`

## SSL Setup

After adding a domain with `--ssl`:

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Get SSL certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal is handled by certbot
```

## Troubleshooting

```bash
# Check nginx status
./nginx-status.sh

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# View logs
sudo tail -f /var/log/nginx/proxy/*_access.log
```
