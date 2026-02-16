#!/usr/bin/env sh
#
# Start application + ELK stack on production server.
# Usage: ./prod-up.sh [--app-only | --elk-only]
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

APP_ONLY=false
ELK_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --app-only) APP_ONLY=true ;;
    --elk-only) ELK_ONLY=true ;;
    -h|--help)
      echo "Usage: $0 [--app-only | --elk-only]"
      echo "  (no args)  - Start app + ELK"
      echo "  --app-only - Start app only"
      echo "  --elk-only - Start ELK stack only"
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
  echo "[prod-up] Pulling app images..."
  docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
  echo "[prod-up] Starting app..."
  docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build
}

start_elk() {
  echo "[prod-up] Starting ELK stack..."
  docker compose -f docker-compose-elk.yml up -d
}

if [ "${ELK_ONLY}" = true ]; then
  start_elk
elif [ "${APP_ONLY}" = true ]; then
  start_app
else
  start_app
  start_elk
fi

echo "[prod-up] Done. Check: docker compose -f docker-compose.yml -f docker-compose.prod.yml ps"
echo "[prod-up] ELK:      docker compose -f docker-compose-elk.yml ps"
