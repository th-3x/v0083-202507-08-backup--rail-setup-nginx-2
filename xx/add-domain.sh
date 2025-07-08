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
