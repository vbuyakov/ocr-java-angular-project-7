# ELK KPI Fix Scripts

Scripts for fixing ELK data and dashboards per the KPI/DORA setup prompt.

## fix-kibana-dashboards.sh

Fixes field name mismatch in existing Kibana dashboards:

| Wrong field              | Correct field  |
|--------------------------|----------------|
| `response.keyword`       | `http_status`  |
| `http.response.status_code` | `http_status` |
| `url.path`               | `request_uri`  |
| `source.ip`             | `client_ip`    |

**Usage:**
```bash
# From project root
KIBANA_URL=https://ocr-ja7-elk.buyakov.com bash misc/elk/scripts/fix-kibana-dashboards.sh
```

**Requirements:** `curl`, `jq` (optional), `ELASTIC_PASSWORD`

**Note:** Kibana must be reachable. For local ELK: `KIBANA_URL=http://127.0.0.1:5601`

## fix-elk-kpi-data.sh (master script)

Orchestrates the full fix flow:

1. Fix Kibana dashboard field names
2. Apply Filebeat ingest pipeline (with `request_time` grok)
3. Restart nginx (emits new log format)
4. Restart Filebeat
5. Update `docs/kpi-dora-analysis.md`

**Usage:**
```bash
bash misc/elk/fix-elk-kpi-data.sh [--skip-kibana] [--skip-nginx] [--skip-docs]
```

**Execution order (manual steps after script):**
- Wait 2–3 min for new logs with `request_time`
- Create KPI2 lens in Kibana (Taux d'erreurs 4xx/5xx)
- Create KPI3 lens (P50/P95 of `request_time`)
- Add KQL saved search: `http_status >= 500`
