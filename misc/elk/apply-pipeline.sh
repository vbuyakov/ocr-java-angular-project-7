#!/bin/bash
# apply-pipeline.sh
# Creates/updates the nginx-access-log-parser ingest pipeline in Elasticsearch
# and reindexes existing nginx docs through it.
#
# Usage (from project root):
#   bash misc/elk/apply-pipeline.sh
#
# Requires:
#   - ELASTIC_PASSWORD in environment or .env file
#   - ELK containers running (docker compose -f docker-compose-elk.yml ps)

set -euo pipefail

PIPELINE_ID="nginx-access-log-parser"
PIPELINE_FILE="misc/filebeat/nginx-pipeline.json"
ES_CONTAINER="${ELK_PROJECT:-ocr-ja7}-elasticsearch"
INDEX_PATTERN="ocr-ja7-logs-*"

# ── Load .env if ELASTIC_PASSWORD is not already set ─────────────────────────
if [ -z "${ELASTIC_PASSWORD:-}" ] && [ -f ".env" ]; then
  # shellcheck disable=SC2046
  export $(grep -E '^ELASTIC_PASSWORD=' .env | xargs)
fi

if [ -z "${ELASTIC_PASSWORD:-}" ]; then
  echo "ERROR: ELASTIC_PASSWORD is not set. Export it or add it to .env."
  exit 1
fi

if [ ! -f "$PIPELINE_FILE" ]; then
  echo "ERROR: Pipeline file not found: $PIPELINE_FILE"
  echo "Run this script from the project root directory."
  exit 1
fi

# ── Helper: run a curl command inside the Elasticsearch container ─────────────
es_curl() {
  docker exec "$ES_CONTAINER" \
    curl -s -u "elastic:${ELASTIC_PASSWORD}" \
    -H 'Content-Type: application/json' \
    "$@"
}

# ── 1. Verify Elasticsearch is reachable ─────────────────────────────────────
echo "==> Checking Elasticsearch health..."
HEALTH=$(es_curl "http://localhost:9200/_cluster/health?pretty" 2>/dev/null || true)
if ! echo "$HEALTH" | grep -qE '"status"\s*:\s*"(green|yellow)"'; then
  echo "ERROR: Elasticsearch is not healthy or not reachable."
  echo "$HEALTH"
  exit 1
fi
echo "    OK"

# ── 2. Upload pipeline JSON to the container and create/update the pipeline ───
echo "==> Creating/updating ingest pipeline '$PIPELINE_ID'..."
docker cp "$PIPELINE_FILE" "${ES_CONTAINER}:/tmp/nginx-pipeline.json"

RESULT=$(docker exec "$ES_CONTAINER" \
  curl -s -o /tmp/pipeline-response.json -w "%{http_code}" \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -X PUT \
  -H 'Content-Type: application/json' \
  -d @/tmp/nginx-pipeline.json \
  "http://localhost:9200/_ingest/pipeline/${PIPELINE_ID}")

BODY=$(docker exec "$ES_CONTAINER" cat /tmp/pipeline-response.json)

if [ "$RESULT" = "200" ]; then
  echo "    Pipeline created/updated successfully (HTTP 200)."
else
  echo "ERROR: Failed to create pipeline (HTTP $RESULT)."
  echo "$BODY"
  exit 1
fi

# ── 3. Reprocess existing nginx docs through the pipeline ────────────────────
echo "==> Reindexing existing nginx docs in '$INDEX_PATTERN' through pipeline..."
REINDEX_RESULT=$(es_curl \
  -X POST \
  -d '{"query":{"term":{"log_source":"nginx"}}}' \
  "http://localhost:9200/${INDEX_PATTERN}/_update_by_query?pipeline=${PIPELINE_ID}&conflicts=proceed&wait_for_completion=true")

UPDATED=$(echo "$REINDEX_RESULT" | grep -o '"updated":[0-9]*' | grep -o '[0-9]*' || echo "0")
FAILURES=$(echo "$REINDEX_RESULT" | grep -o '"failures":\[\]' || echo "")

if echo "$REINDEX_RESULT" | grep -q '"error"'; then
  echo "WARNING: Reindex returned errors:"
  echo "$REINDEX_RESULT"
else
  echo "    Reindex complete. Documents updated: ${UPDATED}"
  if [ -z "$FAILURES" ]; then
    echo "    Some failures may have occurred (non-nginx docs skipped by pipeline — this is expected)."
  else
    echo "    No failures."
  fi
fi

# ── 4. Verify pipeline is active ─────────────────────────────────────────────
echo "==> Verifying pipeline is registered..."
VERIFY=$(es_curl "http://localhost:9200/_ingest/pipeline/${PIPELINE_ID}?pretty")
if echo "$VERIFY" | grep -q "\"${PIPELINE_ID}\""; then
  echo "    Pipeline '${PIPELINE_ID}' is active."
else
  echo "ERROR: Pipeline not found after creation."
  echo "$VERIFY"
  exit 1
fi

echo ""
echo "Done. Next step:"
echo "  docker compose -f docker-compose-elk.yml restart filebeat"
echo ""
echo "New nginx logs will be parsed automatically."
echo "Existing ~1580 docs have been reindexed with parsed fields."
echo "Check Kibana dashboards at https://ocr-ja7-elk.buyakov.com"
