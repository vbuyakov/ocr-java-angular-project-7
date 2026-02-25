#!/bin/bash
# fix-kibana-dashboards.sh
# Task 1: Fix field name mismatch in existing Kibana dashboards.
# Exports dashboards/visualizations/lens, replaces wrong field names, re-imports.
#
# Field mappings:
#   response.keyword          → http_status
#   http.response.status_code → http_status
#   url.path                  → request_uri
#   source.ip                 → client_ip
#
# Usage:
#   bash misc/elk/scripts/fix-kibana-dashboards.sh
#
# Requires:
#   - KIBANA_URL (default: http://127.0.0.1:5601)
#   - ELASTIC_PASSWORD in env or .env
#   - curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KIBANA_URL="${KIBANA_URL:-http://127.0.0.1:5601}"
EXPORT_FILE="${EXPORT_FILE:-/tmp/kibana-export-$(date +%Y%m%d-%H%M%S).ndjson}"
IMPORT_FILE="${IMPORT_FILE:-}"

# Load .env if ELASTIC_PASSWORD is not set
if [ -z "${ELASTIC_PASSWORD:-}" ] && [ -f "$PROJECT_ROOT/.env" ]; then
  # shellcheck disable=SC2046
  export $(grep -E '^ELASTIC_PASSWORD=' "$PROJECT_ROOT/.env" | xargs)
fi

if [ -z "${ELASTIC_PASSWORD:-}" ]; then
  echo "ERROR: ELASTIC_PASSWORD is not set. Export it or add to .env."
  exit 1
fi

# Ensure URL has no trailing slash
KIBANA_URL="${KIBANA_URL%/}"

echo "==> Kibana URL: $KIBANA_URL"
echo "==> Exporting saved objects (dashboard, visualization, lens)..."

HTTP_CODE=$(curl -s -o "$EXPORT_FILE" -w "%{http_code}" \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -X POST \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"type": ["dashboard", "visualization", "lens"]}' \
  "$KIBANA_URL/api/saved_objects/_export")

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: Export failed (HTTP $HTTP_CODE). Check Kibana URL and credentials."
  cat "$EXPORT_FILE" 2>/dev/null | head -20
  exit 1
fi

LINES=$(wc -l < "$EXPORT_FILE")
if [ "$LINES" -eq 0 ]; then
  echo "WARNING: No objects exported (empty file). Nothing to fix."
  exit 0
fi

echo "    Exported $LINES lines to $EXPORT_FILE"

# Create fixed copy
FIXED_FILE="${EXPORT_FILE}.fixed"
cp "$EXPORT_FILE" "$FIXED_FILE"

# Replace field names (order matters for nested replacements)
echo "==> Replacing field names..."
sed -i.bak \
  -e 's/response\.keyword/http_status/g' \
  -e 's/http\.response\.status_code/http_status/g' \
  -e 's/url\.path/request_uri/g' \
  -e 's/source\.ip/client_ip/g' \
  "$FIXED_FILE"
rm -f "${FIXED_FILE}.bak"

# Count replacements
CHANGES=$(diff "$EXPORT_FILE" "$FIXED_FILE" | grep -c '^[<>]' || true)
echo "    Applied replacements ($CHANGES lines changed)"

# Re-import
echo "==> Re-importing fixed objects (overwriteExisting=true)..."
IMPORT_RESP=$(curl -s -w "\n%{http_code}" \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -X POST \
  -H "kbn-xsrf: true" \
  -F "file=@$FIXED_FILE" \
  -F "overwrite=true" \
  "$KIBANA_URL/api/saved_objects/_import")

HTTP_BODY=$(echo "$IMPORT_RESP" | head -n -1)
HTTP_CODE=$(echo "$IMPORT_RESP" | tail -1)

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: Import failed (HTTP $HTTP_CODE)."
  echo "$HTTP_BODY" | jq . 2>/dev/null || echo "$HTTP_BODY"
  exit 1
fi

# Parse import result
SUCCESS=$(echo "$HTTP_BODY" | jq -r '.success' 2>/dev/null || echo "unknown")
if [ "$SUCCESS" = "true" ]; then
  echo "    Import successful."
else
  echo "WARNING: Import may have had issues:"
  echo "$HTTP_BODY" | jq . 2>/dev/null || echo "$HTTP_BODY"
fi

# Cleanup
rm -f "$EXPORT_FILE" "$FIXED_FILE"

echo ""
echo "Done. Refresh Kibana dashboards to see corrected field references."
echo "  Dashboards: Trafic HTTP & Disponibilité, Erreurs & Anomalies, Performance & KPIs"
echo ""
