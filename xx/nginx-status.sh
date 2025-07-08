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
