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

# Check if SSL certificates exist when SSL is requested
SSL_CERT_EXISTS=false
if [ "$ENABLE_SSL" = true ]; then
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
        SSL_CERT_EXISTS=true
    fi
fi

sudo tee "$CONFIG_FILE" > /dev/null << NGINX_EOF
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
NGINX_EOF

# Add SSL configuration if requested and certificates are available
if [ "$ENABLE_SSL" = true ] && [ "$SSL_CERT_EXISTS" = true ]; then
    sudo tee -a "$CONFIG_FILE" > /dev/null << SSL_EOF

# SSL Configuration (certificates found)
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
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
SSL_EOF
elif [ "$ENABLE_SSL" = true ]; then
    # SSL requested but no certificates - create placeholder file
    SSL_CONFIG_FILE="/etc/nginx/proxy-configs/${DOMAIN}-ssl-pending.conf"
    sudo tee "$SSL_CONFIG_FILE" > /dev/null << SSL_PENDING_EOF
# SSL Configuration for $DOMAIN (DISABLED - No certificates found)
# Run: sudo certbot --nginx -d $DOMAIN
# Then: sudo mv $SSL_CONFIG_FILE ${CONFIG_FILE%.*}-ssl-ready.conf.disabled

# server {
#     listen 443 ssl http2;
#     server_name $DOMAIN;
#     
#     ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
#     
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
#     ssl_prefer_server_ciphers off;
#     
#     access_log /var/log/nginx/proxy/${SAFE_DOMAIN}_ssl_access.log;
#     error_log /var/log/nginx/proxy/${SAFE_DOMAIN}_ssl_error.log;
#     
#     limit_req zone=$RATE_LIMIT burst=20 nodelay;
#     
#     location / {
#         proxy_pass http://$UPSTREAM_NAME;
#         proxy_set_header Host \$host;
#         proxy_set_header X-Real-IP \$remote_addr;
#         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto https;
#         proxy_set_header X-Forwarded-Host \$server_name;
#         
#         proxy_connect_timeout 30s;
#         proxy_send_timeout 30s;
#         proxy_read_timeout 30s;
#         
#         proxy_buffering on;
#         proxy_redirect off;
#     }
#     
#     location /nginx-health {
#         access_log off;
#         return 200 "OK SSL - $DOMAIN -> localhost:$TO_PORT\\n";
#         add_header Content-Type text/plain;
#     }
# }
SSL_PENDING_EOF
fi

# Update /etc/hosts if not already present
if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "127.0.0.1    $DOMAIN" | sudo tee -a /etc/hosts > /dev/null
    echo "✓ Added $DOMAIN to /etc/hosts"
fi

# Create status file for web interface
sudo tee "/var/www/html/domains/${DOMAIN}.html" > /dev/null << STATUS_EOF
<!DOCTYPE html>
<html>
<head><title>$DOMAIN Proxy Status</title></head>
<body>
    <h2>$DOMAIN</h2>
    <p><strong>Target:</strong> localhost:$TO_PORT</p>
    <p><strong>Rate Limit:</strong> $RATE_LIMIT</p>
    <p><strong>SSL:</strong> $([ "$ENABLE_SSL" = true ] && [ "$SSL_CERT_EXISTS" = true ] && echo "Enabled" || [ "$ENABLE_SSL" = true ] && echo "Pending Certificates" || echo "Disabled")</p>
    <p><strong>Config:</strong> $CONFIG_FILE</p>
    <p><a href="http://$DOMAIN">Visit Site</a> | <a href="http://$DOMAIN/nginx-health">Health Check</a></p>
    $([ "$ENABLE_SSL" = true ] && [ "$SSL_CERT_EXISTS" = true ] && echo "<p><a href='https://$DOMAIN'>HTTPS Site</a> | <a href='https://$DOMAIN/nginx-health'>HTTPS Health</a></p>")
</body>
</html>
STATUS_EOF

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
        if [ "$SSL_CERT_EXISTS" = true ]; then
            echo "🔒 SSL: Enabled - https://$DOMAIN"
        else
            echo "🔒 SSL: Pending - Run 'sudo certbot --nginx -d $DOMAIN' to enable"
            echo "📄 SSL config ready: /etc/nginx/proxy-configs/${DOMAIN}-ssl-pending.conf"
        fi
    fi
else
    echo "❌ nginx configuration error"
    sudo rm -f "$CONFIG_FILE"
    exit 1
fi