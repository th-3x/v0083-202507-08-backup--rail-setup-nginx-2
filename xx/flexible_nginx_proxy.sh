#!/bin/bash

# Flexible nginx Proxy Management System
# Creates multiple scripts for easy domain and port management

# Script 1: setup-nginx.sh - Initial nginx setup
cat > setup-nginx.sh << 'EOF'
#!/bin/bash

# nginx Initial Setup Script
echo "🔧 Setting up nginx proxy system..."

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "Installing nginx..."
    sudo apt update && sudo apt install nginx -y
    echo "✓ nginx installed"
else
    echo "✓ nginx already installed"
fi

# Create directories for our proxy configs
sudo mkdir -p /etc/nginx/proxy-configs
sudo mkdir -p /var/log/nginx/proxy

# Create main proxy configuration template
sudo tee /etc/nginx/proxy-configs/00-main.conf > /dev/null << 'MAIN_EOF'
# Main proxy configuration
# Individual domain configs will be included automatically

# Rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=web:10m rate=30r/s;

# Upstream definitions will be added here by add-domain.sh
MAIN_EOF

# Update main nginx.conf to include our proxy configs
if ! grep -q "proxy-configs" /etc/nginx/nginx.conf; then
    sudo sed -i '/http {/a\\tinclude /etc/nginx/proxy-configs/*.conf;' /etc/nginx/nginx.conf
    echo "✓ Updated nginx.conf to include proxy configs"
fi

# Remove default site
sudo rm -f /etc/nginx/sites-enabled/default

# Create a status page
sudo tee /etc/nginx/sites-available/proxy-status > /dev/null << 'STATUS_EOF'
server {
    listen 8080;
    server_name localhost;
    
    location /status {
        access_log off;
        return 200 "nginx proxy system active\n";
        add_header Content-Type text/plain;
    }
    
    location /domains {
        root /var/www/html;
        autoindex on;
        try_files $uri $uri/ =404;
    }
}
STATUS_EOF

sudo ln -sf /etc/nginx/sites-available/proxy-status /etc/nginx/sites-enabled/
sudo mkdir -p /var/www/html/domains

# Test nginx configuration
if sudo nginx -t; then
    sudo systemctl enable nginx
    sudo systemctl restart nginx
    echo "✅ nginx proxy system setup complete!"
    echo ""
    echo "Status page: http://localhost:8080/status"
    echo "Domains list: http://localhost:8080/domains"
else
    echo "❌ nginx configuration error"
    exit 1
fi
EOF

chmod +x setup-nginx.sh

# Script 2: add-domain.sh - Add domain proxy
cat > add-domain.sh << 'EOF'
#!/bin/bash

# Add Domain Proxy Script
# Usage: ./add-domain.sh --domain example.com --toPort 3000 [--ssl] [--rate-limit web|api]

# Default values
DOMAIN=""
TO_PORT=""
ENABLE_SSL=false
RATE_LIMIT="web"
FROM_PORT=80

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --toPort)
            TO_PORT="$2"
            shift 2
            ;;
        --fromPort)
            FROM_PORT="$2"
            shift 2
            ;;
        --ssl)
            ENABLE_SSL=true
            shift
            ;;
        --rate-limit)
            RATE_LIMIT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --domain DOMAIN --toPort PORT [OPTIONS]"
            echo ""
            echo "Required:"
            echo "  --domain DOMAIN     Domain name (e.g., version-01.abc.com)"
            echo "  --toPort PORT       Target port (e.g., 3000)"
            echo ""
            echo "Optional:"
            echo "  --fromPort PORT     Source port (default: 80)"
            echo "  --ssl               Enable SSL/HTTPS (requires certbot)"
            echo "  --rate-limit ZONE   Rate limiting: web|api (default: web)"
            echo "  --help, -h          Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --domain version-01.abc.com --toPort 3000"
            echo "  $0 --domain api.abc.com --toPort 4000 --ssl --rate-limit api"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DOMAIN" || -z "$TO_PORT" ]]; then
    echo "❌ Error: --domain and --toPort are required"
    echo "Use --help for usage information"
    exit 1
fi

# Validate port number
if ! [[ "$TO_PORT" =~ ^[0-9]+$ ]] || [ "$TO_PORT" -lt 1 ] || [ "$TO_PORT" -gt 65535 ]; then
    echo "❌ Error: Invalid port number: $TO_PORT"
    exit 1
fi

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "❌ Error: nginx is not running. Run ./setup-nginx.sh first"
    exit 1
fi

echo "🌐 Adding domain proxy: $DOMAIN -> localhost:$TO_PORT"

# Create domain-specific config file
CONFIG_FILE="/etc/nginx/proxy-configs/${DOMAIN}.conf"
SAFE_DOMAIN=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9.-]/_/g')

# Create upstream definition
UPSTREAM_NAME="backend_${SAFE_DOMAIN//./_}_${TO_PORT}"

sudo tee "$CONFIG_FILE" > /dev/null << EOF
# Proxy configuration for $DOMAIN
upstream $UPSTREAM_NAME {
    server 127.0.0.1:$TO_PORT;
    keepalive 32;
}

server {
    listen $FROM_PORT;
    server_name $DOMAIN;
    
    # Logging
    access_log /var/log/nginx/proxy/${SAFE_DOMAIN}_access.log;
    error_log /var/log/nginx/proxy/${SAFE_DOMAIN}_error.log;
    
    # Rate limiting
    limit_req zone=$RATE_LIMIT burst=20 nodelay;
    
    # Proxy settings
    location / {
        proxy_pass http://$UPSTREAM_NAME;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # Buffering
        proxy_buffering on;
        proxy_redirect off;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "OK - $DOMAIN -> localhost:$TO_PORT\\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Add SSL configuration if requested
if [ "$ENABLE_SSL" = true ]; then
    sudo tee -a "$CONFIG_FILE" > /dev/null << EOF

# SSL Configuration (requires certbot setup)
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL certificates (run: sudo certbot --nginx -d $DOMAIN)
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Same proxy configuration as HTTP
    access_log /var/log/nginx/proxy/${SAFE_DOMAIN}_ssl_access.log;
    error_log /var/log/nginx/proxy/${SAFE_DOMAIN}_ssl_error.log;
    
    limit_req zone=$RATE_LIMIT burst=20 nodelay;
    
    location / {
        proxy_pass http://$UPSTREAM_NAME;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        proxy_buffering on;
        proxy_redirect off;
    }
    
    location /nginx-health {
        access_log off;
        return 200 "OK SSL - $DOMAIN -> localhost:$TO_PORT\\n";
        add_header Content-Type text/plain;
    }
}
EOF
    echo "⚠️  SSL configuration added but disabled. Run: sudo certbot --nginx -d $DOMAIN"
fi

# Update /etc/hosts if not already present
if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "127.0.0.1    $DOMAIN" | sudo tee -a /etc/hosts > /dev/null
    echo "✓ Added $DOMAIN to /etc/hosts"
fi

# Create status file for web interface
sudo tee "/var/www/html/domains/${DOMAIN}.html" > /dev/null << EOF
<!DOCTYPE html>
<html>
<head><title>$DOMAIN Proxy Status</title></head>
<body>
    <h2>$DOMAIN</h2>
    <p><strong>Target:</strong> localhost:$TO_PORT</p>
    <p><strong>Rate Limit:</strong> $RATE_LIMIT</p>
    <p><strong>SSL:</strong> $([ "$ENABLE_SSL" = true ] && echo "Enabled" || echo "Disabled")</p>
    <p><strong>Config:</strong> $CONFIG_FILE</p>
    <p><a href="http://$DOMAIN">Visit Site</a> | <a href="http://$DOMAIN/nginx-health">Health Check</a></p>
</body>
</html>
EOF

# Test nginx configuration
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ Domain proxy added successfully!"
    echo ""
    echo "🌐 Domain: http://$DOMAIN"
    echo "🎯 Target: localhost:$TO_PORT"
    echo "📊 Health: http://$DOMAIN/nginx-health"
    echo "📋 Status: http://localhost:8080/domains/$DOMAIN.html"
    
    if [ "$ENABLE_SSL" = true ]; then
        echo "🔒 SSL: Run 'sudo certbot --nginx -d $DOMAIN' to enable"
    fi
else
    echo "❌ nginx configuration error"
    sudo rm -f "$CONFIG_FILE"
    exit 1
fi
EOF

chmod +x add-domain.sh

# Script 3: remove-domain.sh - Remove domain proxy
cat > remove-domain.sh << 'EOF'
#!/bin/bash

# Remove Domain Proxy Script
# Usage: ./remove-domain.sh --domain example.com

DOMAIN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --domain DOMAIN"
            echo ""
            echo "Remove a domain proxy configuration"
            echo ""
            echo "Example:"
            echo "  $0 --domain version-01.abc.com"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    echo "❌ Error: --domain is required"
    exit 1
fi

echo "🗑️  Removing domain proxy: $DOMAIN"

CONFIG_FILE="/etc/nginx/proxy-configs/${DOMAIN}.conf"
SAFE_DOMAIN=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9.-]/_/g')

# Remove nginx config
if [ -f "$CONFIG_FILE" ]; then
    sudo rm "$CONFIG_FILE"
    echo "✓ Removed nginx configuration"
fi

# Remove log files
sudo rm -f "/var/log/nginx/proxy/${SAFE_DOMAIN}_"*

# Remove status file
sudo rm -f "/var/www/html/domains/${DOMAIN}.html"

# Remove from /etc/hosts (only our entries)
sudo sed -i "/127\.0\.0\.1[[:space:]]*${DOMAIN}$/d" /etc/hosts

# Test and reload nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ Domain proxy removed successfully!"
else
    echo "❌ nginx configuration error"
    exit 1
fi
EOF

chmod +x remove-domain.sh

# Script 4: list-domains.sh - List all configured domains
cat > list-domains.sh << 'EOF'
#!/bin/bash

# List Domain Proxies Script

echo "📋 Configured Domain Proxies:"
echo "================================"

if [ ! -d "/etc/nginx/proxy-configs" ]; then
    echo "❌ nginx proxy system not set up. Run ./setup-nginx.sh first"
    exit 1
fi

# Count total domains
TOTAL=$(find /etc/nginx/proxy-configs -name "*.conf" ! -name "00-main.conf" | wc -l)

if [ "$TOTAL" -eq 0 ]; then
    echo "No domains configured yet."
    echo ""
    echo "Add a domain with:"
    echo "  ./add-domain.sh --domain example.com --toPort 3000"
    exit 0
fi

echo "Total domains: $TOTAL"
echo ""

# List each domain configuration
for config in /etc/nginx/proxy-configs/*.conf; do
    if [[ "$(basename "$config")" == "00-main.conf" ]]; then
        continue
    fi
    
    DOMAIN=$(basename "$config" .conf)
    
    # Extract information from config file
    if [ -f "$config" ]; then
        TARGET=$(grep "server 127.0.0.1" "$config" | head -1 | sed 's/.*127.0.0.1://;s/;//')
        RATE_LIMIT=$(grep "limit_req zone=" "$config" | head -1 | sed 's/.*zone=//;s/ .*//')
        SSL_ENABLED=$(grep -q "listen 443" "$config" && echo "Yes" || echo "No")
        
        echo "🌐 Domain: $DOMAIN"
        echo "   Target: localhost:$TARGET"
        echo "   Rate Limit: $RATE_LIMIT"
        echo "   SSL: $SSL_ENABLED"
        echo "   Health: http://$DOMAIN/nginx-health"
        echo ""
    fi
done

echo "Manage domains:"
echo "  Add:    ./add-domain.sh --domain DOMAIN --toPort PORT"
echo "  Remove: ./remove-domain.sh --domain DOMAIN"
echo "  Status: http://localhost:8080/domains"
EOF

chmod +x list-domains.sh

# Script 5: nginx-status.sh - Show nginx status and logs
cat > nginx-status.sh << 'EOF'
#!/bin/bash

# nginx Status and Logs Script

echo "🔍 nginx Proxy System Status"
echo "============================"

# nginx service status
echo "📊 Service Status:"
if systemctl is-active --quiet nginx; then
    echo "   ✅ nginx is running"
    echo "   📈 Uptime: $(systemctl show nginx --property=ActiveEnterTimestamp --value | xargs -I {} date -d {} +'%Y-%m-%d %H:%M:%S')"
else
    echo "   ❌ nginx is not running"
fi

echo ""

# Configuration test
echo "⚙️  Configuration Test:"
if sudo nginx -t 2>/dev/null; then
    echo "   ✅ Configuration is valid"
else
    echo "   ❌ Configuration has errors:"
    sudo nginx -t
fi

echo ""

# Active connections
echo "🔗 Active Connections:"
if command -v ss &> /dev/null; then
    HTTP_CONN=$(ss -tlnp | grep :80 | wc -l)
    HTTPS_CONN=$(ss -tlnp | grep :443 | wc -l)
    echo "   HTTP (port 80): $HTTP_CONN listeners"
    echo "   HTTPS (port 443): $HTTPS_CONN listeners"
fi

echo ""

# Recent access logs (last 10 lines)
echo "📋 Recent Access (last 10 requests):"
if [ -d /var/log/nginx/proxy ]; then
    sudo tail -n 10 /var/log/nginx/proxy/*_access.log 2>/dev/null | head -10 || echo "   No recent access logs"
else
    echo "   No proxy logs directory"
fi

echo ""

# Error logs (last 5 lines)
echo "⚠️  Recent Errors (last 5):"
if [ -d /var/log/nginx/proxy ]; then
    sudo tail -n 5 /var/log/nginx/proxy/*_error.log 2>/dev/null | head -5 || echo "   No recent errors"
else
    echo "   No proxy logs directory"
fi

echo ""
echo "📊 Full status: http://localhost:8080/status"
echo "📋 Domain list: http://localhost:8080/domains"
EOF

chmod +x nginx-status.sh

# Create README
cat > README.md << 'EOF'
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
EOF

echo ""
echo "🎉 Flexible nginx Proxy Management System Created!"
echo ""
echo "📁 Files created:"
echo "   setup-nginx.sh      - Initial nginx setup"
echo "   add-domain.sh       - Add domain proxy"
echo "   remove-domain.sh    - Remove domain proxy" 
echo "   list-domains.sh     - List all domains"
echo "   nginx-status.sh     - Show nginx status"
echo "   README.md           - Documentation"
echo ""
echo "🚀 Quick start:"
echo "   1. ./setup-nginx.sh"
echo "   2. ./add-domain.sh --domain version-01.abc.com --toPort 3000"
echo "   3. ./list-domains.sh"
echo ""
echo "💡 Examples:"
echo "   ./add-domain.sh --domain v1.abc.com --toPort 3001"
echo "   ./add-domain.sh --domain api.abc.com --toPort 4000 --ssl"
echo "   ./add-domain.sh --domain dev.abc.com --toPort 8080 --rate-limit api"