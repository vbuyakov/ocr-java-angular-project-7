#!/bin/sh
# Pre-create log file with 644 so Filebeat (non-root) can read it
touch /var/log/caddy/access.log && chmod 644 /var/log/caddy/access.log
exec caddy run --config /app/Caddyfile
