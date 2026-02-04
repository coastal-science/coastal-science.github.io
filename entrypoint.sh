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
if [ "$USE_DECAP" = true ]; then
    echo "USE_DECAP=true: Decap CMS mode enabled. Will generate decap.conf and (if needed) upstreams for CMS/backend."
else
    echo "USE_DECAP=false: Decap CMS mode disabled or unset. Serving static-only site with default.conf."
fi

# sites-available = templates (processed by envsubst); 
# sites-enabled = generated conf ready for nginx to run
mkdir -p /etc/nginx/sites-enabled

if [ -d "/etc/nginx/sites-available" ]; then
    if [ "$USE_DECAP" = true ]; then
        # Decap CMS: server block with /auth, /callback -> cms_upstream; / -> static
        if [ -f "/etc/nginx/sites-available/decap.conf.template" ]; then
            envsubst '$DOMAIN' < /etc/nginx/sites-available/decap.conf.template > /etc/nginx/sites-enabled/decap.conf
            echo "Processed decap.conf.template -> /etc/nginx/sites-enabled/decap.conf (USE_DECAP=true)"
        fi
    else
        # Preview/other: static-only server block
        if [ -f "/etc/nginx/sites-available/default.conf.template" ]; then
            envsubst '$DOMAIN' < /etc/nginx/sites-available/default.conf.template > /etc/nginx/sites-enabled/default.conf
            echo "Processed default.conf.template -> /etc/nginx/sites-enabled/default.conf (USE_DECAP=false)"
        fi
    fi
fi
# Ensure nginx loads sites-enabled (conf.d/*.conf is included by default)
printf '%s\n' 'include /etc/nginx/sites-enabled/*.conf;' > /etc/nginx/conf.d/00-sites-enabled.conf

# Upstreams for Decap (main/production/prod only). Skip if server.conf already present (e.g. Nomad mount).
if [ "$USE_DECAP" = true ] && [ ! -f /etc/nginx/conf.d/server.conf ]; then
    if [ -f /etc/nginx/conf.d/server.conf.template ]; then
        envsubst '$SITE_HOST_PORT $CMS_HOST_PORT' < /etc/nginx/conf.d/server.conf.template > /etc/nginx/conf.d/server.conf
        echo "Processed server.conf.template -> /etc/nginx/conf.d/server.conf"
    elif [ -f /etc/nginx/conf.d/server.conf.local ]; then
        cp /etc/nginx/conf.d/server.conf.local /etc/nginx/conf.d/server.conf
        echo "Copied server.conf.local -> /etc/nginx/conf.d/server.conf"
    fi
fi

echo "All *.conf files in /etc/nginx/conf.d/, /etc/nginx/sites-enabled/, /etc/nginx/sites-available/, and /etc/nginx/sites-unavailable/:"
find /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/nginx/sites-available /etc/nginx/sites-unavailable -maxdepth 1 -name "*.conf" 2>/dev/null | tr '\n' ' '; echo

echo "Contents of /etc/nginx/conf.d/ and /etc/nginx/sites-enabled/:"
find /etc/nginx/conf.d /etc/nginx/sites-enabled -maxdepth 1 -name "*.conf" -type f 2>/dev/null | while read -r conf_file; do
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
