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
