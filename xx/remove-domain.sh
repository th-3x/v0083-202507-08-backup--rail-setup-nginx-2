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
