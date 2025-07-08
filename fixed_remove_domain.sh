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
            echo "Remove a domain proxy configuration and all related files"
            echo ""
            echo "This will remove:"
            echo "  - Main nginx configuration"
            echo "  - SSL pending configuration (if exists)"
            echo "  - SSL ready configuration (if exists)"
            echo "  - Log files"
            echo "  - Status page"
            echo "  - /etc/hosts entry"
            echo ""
            echo "Example:"
            echo "  $0 --domain version-01.abc.com"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    echo "❌ Error: --domain is required"
    echo "Use --help for usage information"
    exit 1
fi

echo "🗑️  Removing domain proxy: $DOMAIN"

CONFIG_DIR="/etc/nginx/proxy-configs"
SAFE_DOMAIN=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9.-]/_/g')

# Define all possible config files
MAIN_CONFIG="${CONFIG_DIR}/${DOMAIN}.conf"
SSL_PENDING_CONFIG="${CONFIG_DIR}/${DOMAIN}-ssl-pending.conf"
SSL_READY_CONFIG="${CONFIG_DIR}/${DOMAIN}-ssl-ready.conf"
SSL_READY_DISABLED="${CONFIG_DIR}/${DOMAIN}-ssl-ready.conf.disabled"

FILES_REMOVED=0

# Remove main nginx config
if [ -f "$MAIN_CONFIG" ]; then
    sudo rm "$MAIN_CONFIG"
    echo "✓ Removed main nginx configuration: ${DOMAIN}.conf"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

# Remove SSL pending config
if [ -f "$SSL_PENDING_CONFIG" ]; then
    sudo rm "$SSL_PENDING_CONFIG"
    echo "✓ Removed SSL pending configuration: ${DOMAIN}-ssl-pending.conf"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

# Remove SSL ready config
if [ -f "$SSL_READY_CONFIG" ]; then
    sudo rm "$SSL_READY_CONFIG"
    echo "✓ Removed SSL ready configuration: ${DOMAIN}-ssl-ready.conf"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

# Remove SSL ready disabled config
if [ -f "$SSL_READY_DISABLED" ]; then
    sudo rm "$SSL_READY_DISABLED"
    echo "✓ Removed SSL ready disabled configuration: ${DOMAIN}-ssl-ready.conf.disabled"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

# Remove any other domain-related config files (wildcard cleanup)
OTHER_CONFIGS=$(find "$CONFIG_DIR" -name "${DOMAIN}*" 2>/dev/null)
if [ -n "$OTHER_CONFIGS" ]; then
    for config in $OTHER_CONFIGS; do
        if [ -f "$config" ]; then
            sudo rm "$config"
            echo "✓ Removed additional config: $(basename "$config")"
            FILES_REMOVED=$((FILES_REMOVED + 1))
        fi
    done
fi

# Remove log files (both HTTP and SSL logs)
LOG_FILES_REMOVED=0
for log_pattern in "${SAFE_DOMAIN}_access.log" "${SAFE_DOMAIN}_error.log" "${SAFE_DOMAIN}_ssl_access.log" "${SAFE_DOMAIN}_ssl_error.log"; do
    if [ -f "/var/log/nginx/proxy/$log_pattern" ]; then
        sudo rm "/var/log/nginx/proxy/$log_pattern"
        LOG_FILES_REMOVED=$((LOG_FILES_REMOVED + 1))
    fi
done

if [ $LOG_FILES_REMOVED -gt 0 ]; then
    echo "✓ Removed $LOG_FILES_REMOVED log file(s)"
fi

# Remove status file
if [ -f "/var/www/html/domains/${DOMAIN}.html" ]; then
    sudo rm "/var/www/html/domains/${DOMAIN}.html"
    echo "✓ Removed status page: ${DOMAIN}.html"
fi

# Remove from /etc/hosts (only our entries)
if grep -q "127\.0\.0\.1[[:space:]]*${DOMAIN}$" /etc/hosts; then
    sudo sed -i "/127\.0\.0\.1[[:space:]]*${DOMAIN}$/d" /etc/hosts
    echo "✓ Removed from /etc/hosts"
fi

# Check if any files were actually removed
if [ $FILES_REMOVED -eq 0 ]; then
    echo "⚠️  No configuration files found for domain: $DOMAIN"
    echo "   Domain may not have been configured or already removed"
else
    echo "📊 Removed $FILES_REMOVED configuration file(s)"
fi

# Test and reload nginx
echo ""
echo "🔄 Testing nginx configuration..."
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ Domain proxy removed successfully!"
    echo ""
    echo "🧹 Cleanup complete for: $DOMAIN"
    echo "   • Configuration files: $FILES_REMOVED removed"
    echo "   • Log files: $LOG_FILES_REMOVED removed"
    echo "   • Status page: removed"
    echo "   • /etc/hosts: cleaned"
else
    echo "❌ nginx configuration error after removal"
    echo "   You may need to check /etc/nginx/nginx.conf manually"
    exit 1
fi