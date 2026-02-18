#!/bin/sh
# Set kibana_system + logstash_writer, then start Kibana.
# logstash_system only allows .monitoring-logstash-*; we use logstash_writer for ocr-ja7-logs-*
set -e
echo "[kibana] Waiting for Elasticsearch..."
until curl -sf -u "elastic:${ELASTIC_PASSWORD}" "http://elasticsearch:9200/_cluster/health" >/dev/null; do sleep 2; done
echo "[kibana] Setting built-in user passwords..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" -X POST "http://elasticsearch:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d "{\"password\":\"${ELASTIC_PASSWORD}\"}"
echo "[kibana] Creating logstash_writer role and user for ocr-ja7-logs-*..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" -X PUT "http://elasticsearch:9200/_security/role/logstash_writer" -H "Content-Type: application/json" -d '{"cluster":["monitor","manage_index_templates"],"indices":[{"names":["ocr-ja7-logs-*"],"privileges":["create_index","index","create","write","manage"]}]}'
curl -sf -u "elastic:${ELASTIC_PASSWORD}" -X PUT "http://elasticsearch:9200/_security/user/logstash_writer" -H "Content-Type: application/json" -d "{\"password\":\"${ELASTIC_PASSWORD}\",\"roles\":[\"logstash_writer\"]}"
echo "[kibana] Raising cluster shard limit (avoids no_shard_available_action_exception)..."
curl -sf -u "elastic:${ELASTIC_PASSWORD}" -X PUT "http://elasticsearch:9200/_cluster/settings" -H "Content-Type: application/json" -d '{"persistent":{"cluster.max_shards_per_node":2000}}'
exec /usr/local/bin/kibana-docker
