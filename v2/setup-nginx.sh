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
