#!/bin/bash

# Port Redirection Solutions for xx.abc.com:80 -> 127.0.0.1:3000

echo "Setting up port redirection solutions..."

# Solution 1: Update /etc/hosts (basic hostname mapping)
echo "=== Solution 1: /etc/hosts Configuration ==="
cat << 'EOF'
# Add these lines to /etc/hosts (requires sudo):
127.0.0.1    version-01.abc.com
127.0.0.1    version-02.abc.com
127.0.0.1    version-03.abc.com
127.0.0.1    abc.com

# Then access via: http://version-01.abc.com:3000
EOF

# Solution 2: iptables port forwarding (Linux)
echo ""
echo "=== Solution 2: iptables Port Forwarding (Linux) ==="
cat << 'EOF'
# Forward port 80 to 3000 (requires sudo):
sudo iptables -t nat -A OUTPUT -p tcp --dport 80 -d 127.0.0.1 -j REDIRECT --to-port 3000

# Or forward for specific domains:
sudo iptables -t nat -A OUTPUT -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:3000

# To remove rules later:
sudo iptables -t nat -D OUTPUT -p tcp --dport 80 -d 127.0.0.1 -j REDIRECT --to-port 3000
EOF

# Solution 3: socat port forwarding
echo ""
echo "=== Solution 3: socat Port Forwarding ==="
cat << 'EOF'
# Install socat:
sudo apt update && sudo apt install socat -y

# Forward port 80 to 3000:
sudo socat TCP-LISTEN:80,fork TCP:127.0.0.1:3000 &

# To stop:
sudo pkill socat
EOF

# Solution 4: nginx reverse proxy
echo ""
echo "=== Solution 4: nginx Reverse Proxy (Recommended) ==="

# Create nginx configuration
cat > rails_proxy.conf << 'EOF'
server {
    listen 80;
    server_name *.abc.com;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

cat << 'EOF'
# Install nginx:
sudo apt update && sudo apt install nginx -y

# Copy the rails_proxy.conf to nginx:
sudo cp rails_proxy.conf /etc/nginx/sites-available/rails_proxy
sudo ln -s /etc/nginx/sites-available/rails_proxy /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test and reload nginx:
sudo nginx -t
sudo systemctl reload nginx
EOF

# Solution 5: Apache reverse proxy
echo ""
echo "=== Solution 5: Apache Reverse Proxy ==="
cat << 'EOF'
# Install Apache:
sudo apt update && sudo apt install apache2 -y

# Enable required modules:
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod rewrite

# Create virtual host configuration:
sudo tee /etc/apache2/sites-available/rails_proxy.conf > /dev/null << 'APACHE_EOF'
<VirtualHost *:80>
    ServerName abc.com
    ServerAlias *.abc.com
    
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
</VirtualHost>
APACHE_EOF

# Enable site and restart Apache:
sudo a2ensite rails_proxy
sudo a2dissite 000-default
sudo systemctl reload apache2
EOF

# Solution 6: Simple SSH tunnel
echo ""
echo "=== Solution 6: SSH Tunnel (Development) ==="
cat << 'EOF'
# Forward local port 80 to 3000:
sudo ssh -L 80:127.0.0.1:3000 localhost -N &

# Access via: http://version-01.abc.com (port 80 is default)
EOF

# Create setup script for /etc/hosts
cat > setup_hosts.sh << 'EOF'
#!/bin/bash

echo "Adding entries to /etc/hosts..."

# Backup original hosts file
sudo cp /etc/hosts /etc/hosts.backup

# Add our custom domains
sudo tee -a /etc/hosts > /dev/null << 'HOSTS_EOF'

# Rails development domains
127.0.0.1    version-01.abc.com
127.0.0.1    version-02.abc.com
127.0.0.1    version-03.abc.com
127.0.0.1    version-04.abc.com
127.0.0.1    version-05.abc.com
127.0.0.1    abc.com
HOSTS_EOF

echo "✓ Added custom domains to /etc/hosts"
echo "You can now access:"
echo "  - http://version-01.abc.com:3000"
echo "  - http://version-02.abc.com:3000"
echo "  - http://abc.com:3000"
EOF

chmod +x setup_hosts.sh

# Create nginx setup script
cat > setup_nginx.sh << 'EOF'
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
EOF

chmod +x setup_nginx.sh

echo ""
echo "🎉 Created port redirection solution scripts!"
echo ""
echo "Available options:"
echo "  1. Basic /etc/hosts:     ./setup_hosts.sh (still need :3000)"
echo "  2. nginx reverse proxy:  ./setup_nginx.sh (no port needed)"
echo ""
echo "Recommendation: Use nginx reverse proxy for the best experience!"
echo "It will allow you to access http://version-01.abc.com without specifying port 3000"
