#!/bin/bash

echo "Setting up nginx reverse proxy..."

# Install nginx
sudo apt update && sudo apt install nginx -y

# Create nginx configuration
sudo tee /etc/nginx/sites-available/rails_proxy > /dev/null << 'NGINX_EOF'
server {
    listen 80;
    server_name *.abc.com abc.com;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
    }
}
NGINX_EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/rails_proxy /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test and reload nginx
sudo nginx -t && sudo systemctl reload nginx

echo "✓ nginx configured successfully"
echo "Now you can access: http://version-01.abc.com (port 80)"
