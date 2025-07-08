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
