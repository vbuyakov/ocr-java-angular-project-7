#!/usr/bin/env sh
#
# Start or restart application + ELK stack on production server.
# Usage: ./prod-up.sh [--app-only | --elk-only] [--restart]
# Run from project root.
#
# Prerequisites:
#   - docker login ghcr.io
#   - Host Nginx configured for app and Kibana
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
cd "${PROJECT_ROOT}"

# Support both docker compose (v2) and docker-compose (v1)
if docker compose version >/dev/null 2>&1; then
  DCOMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DCOMPOSE="docker-compose"
else
  echo "Error: docker compose or docker-compose required" >&2
  exit 1
fi

APP_ONLY=false
ELK_ONLY=false
RESTART=false

for arg in "$@"; do
  case "$arg" in
    --app-only) APP_ONLY=true ;;
    --elk-only) ELK_ONLY=true ;;
    --restart) RESTART=true ;;
    -h|--help)
      echo "Usage: $0 [--app-only | --elk-only] [--restart]"
      echo "  (no args)   - Start app + ELK (pull images for app)"
      echo "  --app-only - Start app only"
      echo "  --elk-only - Start ELK stack only"
      echo "  --restart  - Restart without pulling (apply config changes)"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "${APP_ONLY}" = true ] && [ "${ELK_ONLY}" = true ]; then
  echo "Cannot use --app-only and --elk-only together" >&2
  exit 1
fi

start_app() {
  if [ "${RESTART}" = false ]; then
    echo "[prod-up] Pulling app images..."
    $DCOMPOSE -f docker-compose.yml -f docker-compose.prod.yml pull
  fi
  echo "[prod-up] Starting app..."
  $DCOMPOSE -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build
}

start_elk() {
  echo "[prod-up] Starting ELK stack..."
  $DCOMPOSE -f docker-compose-elk.yml up -d
}

if [ "${ELK_ONLY}" = true ]; then
  start_elk
elif [ "${APP_ONLY}" = true ]; then
  start_app
else
  start_app
  start_elk
fi

echo "[prod-up] Done. Check: $DCOMPOSE -f docker-compose.yml -f docker-compose.prod.yml ps"
echo "[prod-up] ELK:       $DCOMPOSE -f docker-compose-elk.yml ps"
