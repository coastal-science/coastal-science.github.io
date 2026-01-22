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

cat /etc/nginx/conf.d/*.conf

# Test nginx configuration after processing all configs
# This validates the final configuration with all environment variables substituted
echo "Testing nginx configuration..."
nginx -t


echo Starting NGINX...
# Start NGINX
# exec nginx -g "daemon off;"

# Execute the original nginx entrypoint
# This will also process any .template files in /etc/nginx/templates/ if they exist
# If no arguments provided, use default nginx command to run in foreground
if [ $# -eq 0 ]; then
    exec /docker-entrypoint.sh nginx -g "daemon off;"
else
    exec /docker-entrypoint.sh "$@"
fi
