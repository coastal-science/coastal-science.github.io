#!/bin/sh
set -e

# Process site configurations from sites-available using envsubst
# and copy them to /etc/nginx/conf.d/
if [ -d "/etc/nginx/sites-available" ]; then
    # Use find to handle cases where no .conf files exist
    find /etc/nginx/sites-available -maxdepth 1 -name "*.conf" -type f | while read -r conf_file; do
        # Get the base filename without path
        filename=$(basename "$conf_file")
        # Process with envsubst, only substituting specific variables
        # This prevents envsubst from replacing nginx variables like $http_host, $remote_addr, etc.
        # Only variables explicitly listed in the format string will be substituted
        envsubst '$DOMAIN' < "$conf_file" > "/etc/nginx/conf.d/$filename"
        echo "Processed $conf_file -> /etc/nginx/conf.d/$filename"
    done
fi


if [ ! -f /etc/nginx/conf.d/server.conf ] && [ -f /etc/nginx/conf.d/server.conf.local ]; then
    mv /etc/nginx/conf.d/server.conf.local /etc/nginx/conf.d/server.conf
    echo "Renamed server.conf.local to server.conf in /etc/nginx/conf.d/"
fi

echo "Contents of /etc/nginx/conf.d/:"
find /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-unavailable -maxdepth 1 -name "*.conf" | tr '\n' ' '; echo

find /etc/nginx/conf.d -maxdepth 1 -name "*.conf" -type f | while read -r conf_file; do
    echo "==> $conf_file"
    cat "$conf_file"
    echo ""
done

conf_file=/etc/nginx/nginx.conf
echo "==> $conf_file"
cat "$conf_file"
echo ""

# Test nginx configuration after processing all configs
# This validates the final configuration with all environment variables substituted
echo "Testing nginx configuration..."
nginx -t


echo Starting NGINX...
# Hand off to the original nginx entrypoint (runs /docker-entrypoint.d/, then nginx).
# Keeps behavior aligned with the default nginx:alpine image (e.g. logging).
if [ $# -eq 0 ]; then
    exec /docker-entrypoint.sh nginx -g "daemon off;"
else
    exec /docker-entrypoint.sh "$@"
fi
