#!/bin/bash
# fix-elk-kpi-data.sh — Setup KPI2 & KPI3 in ELK (MicroCRM)
#
# Orchestrates all fixes from the KPI/DORA setup prompt:
#   1. Fix field name mismatch in Kibana dashboards
#   2. Update nginx log format (request_time)
#   3. Update Filebeat ingest pipeline
#   4. Restart nginx for new logs
#   5. Update kpi-dora-analysis.md
#
# Execution order:
#   fix-kibana-dashboards → nginx already updated → apply-pipeline → restart nginx
#
# Usage (from project root):
#   bash misc/elk/fix-elk-kpi-data.sh [--skip-kibana] [--skip-nginx] [--skip-docs]
#
# Env:
#   KIBANA_URL     - Kibana base URL (default: http://127.0.0.1:5601)
#   ELASTIC_PASSWORD - Required for ES/Kibana API

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

SKIP_KIBANA=false
SKIP_NGINX=false
SKIP_DOCS=false

for arg in "$@"; do
  case "$arg" in
    --skip-kibana) SKIP_KIBANA=true ;;
    --skip-nginx)  SKIP_NGINX=true ;;
    --skip-docs)   SKIP_DOCS=true ;;
    -h|--help)
      echo "Usage: $0 [--skip-kibana] [--skip-nginx] [--skip-docs]"
      echo ""
      echo "  --skip-kibana  Skip Kibana dashboard field fix (use if Kibana unreachable)"
      echo "  --skip-nginx   Skip nginx restart (e.g. when config already applied)"
      echo "  --skip-docs    Skip kpi-dora-analysis.md update"
      exit 0
      ;;
  esac
done

echo "=============================================="
echo "  ELK KPI Data Fix — MicroCRM"
echo "=============================================="
echo ""

# ── 1. Fix Kibana dashboards (field name mismatch) ───────────────────────────
if [ "$SKIP_KIBANA" = false ]; then
  echo ">>> Step 1: Fix Kibana dashboard field names"
  if bash "$SCRIPT_DIR/scripts/fix-kibana-dashboards.sh"; then
    echo "    OK"
  else
    echo "    FAILED (non-fatal, continuing)"
  fi
  echo ""
else
  echo ">>> Step 1: Skipped (--skip-kibana)"
  echo ""
fi

# ── 2. Apply ingest pipeline (includes request_time grok) ────────────────────
echo ">>> Step 2: Apply Filebeat ingest pipeline"
if bash "$SCRIPT_DIR/apply-pipeline.sh"; then
  echo "    OK"
else
  echo "    FAILED"
  exit 1
fi
echo ""

# ── 3. Restart nginx (to emit logs with request_time) ────────────────────────
if [ "$SKIP_NGINX" = false ]; then
  echo ">>> Step 3: Restart nginx (new log format)"
  if docker compose ps -q nginx 2>/dev/null | grep -q .; then
    docker compose restart nginx
    echo "    Nginx restarted. Wait 2–3 min for new logs with request_time."
  else
    echo "    WARNING: nginx container not running. Start app first: docker compose up -d"
  fi
  echo ""
else
  echo ">>> Step 3: Skipped (--skip-nginx)"
  echo ""
fi

# ── 4. Restart Filebeat (optional, to pick up pipeline) ──────────────────────
echo ">>> Step 4: Restart Filebeat"
if docker compose -f docker-compose-elk.yml ps -q filebeat 2>/dev/null | grep -q .; then
  docker compose -f docker-compose-elk.yml restart filebeat
  echo "    Filebeat restarted."
else
  echo "    WARNING: Filebeat not running. Start ELK: docker compose -f docker-compose-elk.yml up -d"
fi
echo ""

# ── 5. Update kpi-dora-analysis.md ───────────────────────────────────────────
if [ "$SKIP_DOCS" = false ]; then
  echo ">>> Step 5: Update docs/kpi-dora-analysis.md"
  if [ -f "docs/kpi-dora-analysis.md" ]; then
    # Field replacements in KQL and KPI sections
    sed -i.bak \
      -e 's/http\.response\.status_code/http_status/g' \
      -e 's/upstream_response_time/request_time/g' \
      -e 's/url\.path/request_uri/g' \
      -e 's/container\.name/log_container/g' \
      -e 's/http\.response\.time/request_time/g' \
      docs/kpi-dora-analysis.md
    rm -f docs/kpi-dora-analysis.md.bak
    echo "    Updated field references in kpi-dora-analysis.md"
  else
    echo "    WARNING: docs/kpi-dora-analysis.md not found"
  fi
  echo ""
else
  echo ">>> Step 5: Skipped (--skip-docs)"
  echo ""
fi

echo "=============================================="
echo "  Done"
echo "=============================================="
echo ""
echo "Next steps (manual):"
echo "  1. In Kibana: create KPI2 lens (Taux d'erreurs 4xx/5xx) using http_status"
echo "  2. In Kibana: create KPI3 lens (P50/P95 request_time) after new logs arrive"
echo "  3. Add KQL saved search: http_status >= 500 → 'Erreurs 5xx – Alerting view'"
echo ""
echo "Kibana: ${KIBANA_URL:-http://127.0.0.1:5601}"
echo ""
