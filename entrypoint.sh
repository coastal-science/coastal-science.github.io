#!/bin/sh
set -e

# Reusable: parse a boolean value; echoes "true" or "false", returns 1 on invalid (caller should exit).
# Usage: VAR=$(parse_bool "${VAR:-false}") || exit 1
# Unset/empty is treated as false. Accepts: true|True|TRUE|1|yes|Yes|YES -> true; false|False|FALSE|0|no|No|NO|"" -> false.
parse_bool() {
    _val="${1:-}"
    case "$_val" in
        true|True|TRUE|1|yes|Yes|YES)   echo "true"; return 0 ;;
        false|False|FALSE|0|no|No|NO|"") echo "false"; return 0 ;;
        *)
            echo "Error: Invalid boolean value: '$_val'" >&2
            return 1
            ;;
    esac
}
# Config chosen at runtime via USE_DECAP (set by orchestrator). Unset → false.
# USE_DECAP=true  -> Decap CMS: decap.conf + server.conf
# USE_DECAP=false or unset -> static only: default.conf (safe default)
USE_DECAP=$(parse_bool "${USE_DECAP:-false}") || exit 1

# Process site configurations from sites-available using envsubst
# and copy them to /etc/nginx/conf.d/
if [ -d "/etc/nginx/sites-available" ]; then
    # Use find to handle cases where no .template files exist
    find /etc/nginx/sites-available -maxdepth 1 -name "*.template" -type f | while read -r template_file; do
        # Get the base filename without path and .template suffix
        basefile=$(basename "$template_file" .template)
        [ -z "$basefile" ] && continue
        # Process with envsubst, only substituting specific variables
        # This prevents envsubst from replacing nginx variables like $http_host, $remote_addr, etc.
        envsubst '$DOMAIN' < "$template_file" > "/etc/nginx/conf.d/$basefile"
        echo "Processed $template_file -> /etc/nginx/conf.d/$basefile"
    done
fi


if [ ! -f /etc/nginx/conf.d/server.conf ] && [ -f /etc/nginx/conf.d/server.conf.local ]; then
    mv /etc/nginx/conf.d/server.conf.local /etc/nginx/conf.d/server.conf
    echo "Renamed server.conf.local to server.conf in /etc/nginx/conf.d/"
fi

echo "All *.conf files in /etc/nginx/conf.d/, /etc/nginx/sites-available/, and /etc/nginx/sites-unavailable/:"
find /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-unavailable -maxdepth 1 -name "*.conf" | tr '\n' ' '; echo

echo "Contents of /etc/nginx/conf.d/:"
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
