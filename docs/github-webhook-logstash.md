# GitHub Webhook → Logstash → Elasticsearch

Ce document décrit le pipeline Logstash qui reçoit les webhooks GitHub (événements **Workflow runs**) pour analyser le taux de succès, la durée d'exécution et les métriques des pipelines CI/CD.

---

## Vue d'ensemble

```
GitHub (Workflow run requested/completed)
       │
       │  POST /githubhook (Basic Auth)
       ▼
   Logstash HTTP input (:8002)
       │
       ├── Filter (workflow_run_id, execution_time, result, branch...)
       │
       ▼
   Elasticsearch (index micro-crm-github-actions-YYYY.MM.dd)
       │
       ▼
   Kibana (analyses, dashboards)
```

**Événements GitHub supportés** : *Workflow runs* (workflow run requested or completed on a repository).

---

## Configuration

### 1. Variables d'environnement (.env)

Ajouter ou vérifier dans `.env` :

```bash
# Logstash HTTP input pour GitHub webhook (github.conf)
LOGSTASH_HTTP_PORT=8002
LOGSTASH_HTTP_USER=githubwebhooker
LOGSTASH_HTTP_PASSWORD=somepassword
```

Ces variables sont utilisées par le pipeline `github.conf` pour l'authentification Basic Auth sur l'entrée HTTP.

### 2. Docker Compose

Le service Logstash doit recevoir ces variables. Dans `docker-compose-elk.yml`, le bloc `logstash` doit inclure :

```yaml
environment:
  - "LS_JAVA_OPTS=-Xmx1024m -Xms1024m"
  - ELASTICSEARCH_USER=logstash_writer
  - ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD}
  - LOGSTASH_HTTP_PORT=${LOGSTASH_HTTP_PORT}
  - LOGSTASH_HTTP_USER=${LOGSTASH_HTTP_USER}
  - LOGSTASH_HTTP_PASSWORD=${LOGSTASH_HTTP_PASSWORD}
```

Le port `8002` est exposé sur l'hôte (`127.0.0.1:8002:8002`).

### 3. Configuration GitHub Webhook

1. **Repository** → **Settings** → **Webhooks** → **Add webhook**
2. **Payload URL** (selon votre setup) :
   - **Direct** (port exposé) : `https://LOGSTASH_HTTP_USER:LOGSTASH_HTTP_PASSWORD@ocr-ja7-elk.buyakov.com:8002/`
   - **Via Nginx** (proxy `/githubhook` → Logstash) : `https://LOGSTASH_HTTP_USER:LOGSTASH_HTTP_PASSWORD@ocr-ja7-elk.buyakov.com/githubhook`
3. **Content type** : sélectionner **`application/json`** (menu déroulant)
4. **Which events would you like to trigger this webhook?** :
   - Choisir le bouton radio **Let me select individual events**
   - Dans la liste des cases à cocher, activer uniquement **Workflow runs** (événement déclenché quand un workflow run est demandé ou terminé)
5. **Active** : laisser coché

> **Sécurité** : Utilisez des identifiants forts et évitez d'exposer le port 8002 directement sur Internet. Préférez un reverse proxy Nginx avec SSL.

---

## Structure du pipeline (github.conf)

### Input

| Option | Valeur | Description |
|--------|--------|-------------|
| `host` | `0.0.0.0` | Écoute sur toutes les interfaces |
| `port` | `${LOGSTASH_HTTP_PORT}` | Port HTTP (8002) |
| `user` / `password` | `${LOGSTASH_HTTP_USER}` / `${LOGSTASH_HTTP_PASSWORD}` | Basic Auth |
| `ecs_compatibility` | `disabled` | Schéma non-ECS pour compatibilité |

### Filtres

| Condition | Action |
|-----------|--------|
| `[workflow_run]` présent | Crée `workflow_run_id` = `{id}-{run_attempt}` |
| `[workflow_job]` sans `workflow_run_id` | Crée `workflow_run_id`, `result`, `branch`, `status` à partir de `workflow_job` |
| `[workflow_run][updated_at]` et `run_started_at` | Calcule `execution_time` (secondes) = `updated_at - run_started_at` |
| Tous les événements | Ajoute `source` = `github_webhook` |

### Output

| Destination | Détail |
|-------------|--------|
| **stdout** | JSON (debug) |
| **file** | `/var/log/logstash/http_output.log` |
| **Elasticsearch** | Index `micro-crm-github-actions-%{+YYYY.MM.dd}` |

---

## Index Elasticsearch

- **Pattern** : `micro-crm-github-actions-*`
- **Champs temporel** : `@timestamp`
- **Champs utiles pour l'analyse** :

| Champ | Description |
|-------|-------------|
| `workflow_run_id` | Identifiant unique du run (`id-run_attempt`) |
| `execution_time` | Durée d'exécution en secondes |
| `result` | Conclusion : `success`, `failure`, `cancelled`, etc. |
| `status` | État : `queued`, `in_progress`, `completed` |
| `branch` | Branche concernée (`head_branch`) |
| `workflow_run` | Objet complet du webhook (nom, chemin, etc.) |
| `source` | Toujours `github_webhook` |

---

## Kibana – Analyses recommandées

### 1. Data View

1. **Stack Management** → **Data Views** → **Create data view**
2. **Name** : `GitHub Actions`
3. **Index pattern** : `micro-crm-github-actions-*`
4. **Timestamp field** : `@timestamp`
5. **Save**

### 2. Taux de succès (Change Failure Rate)

- **Discover** ou **Lens** : filtrer `result: success` vs `result: failure`
- **Aggregation** : Count par `result` (pie chart ou bar chart)
- **Formule** : `success_rate = count(result:success) / total * 100`

### 3. Durée d'exécution (Lead Time)

- **Lens** : champ `execution_time` (moyenne, médiane, percentiles)
- **Visualisation** : line chart par jour ou par workflow
- **Filtre** : `result: success` pour exclure les runs annulés/échoués prématurément

### 4. Exemples de requêtes KQL

```
# Runs échoués
result: "failure"

# Runs sur main
branch: "main"

# Runs longs (> 10 min)
execution_time > 600

# Workflow spécifique (adapter le nom)
workflow_run.name: "CI"
```

### 5. Dashboard DORA

Combiner avec [kpi-dora-analysis.md](kpi-dora-analysis.md) pour :
- **Deployment Frequency** : count des runs `completed` avec `result: success`
- **Lead Time for Changes** : `execution_time` moyen
- **Change Failure Rate** : `result: failure` / total

---

## Fichiers

| Fichier | Rôle |
|---------|------|
| `misc/elk/logstash/pipelines/github.conf` | Pipeline Logstash (input HTTP, filtres, output ES) |
| `misc/elk/logstash/pipelines.yml` | Déclaration du pipeline `github-webhook-pipeline` |
| `docker-compose-elk.yml` | Service Logstash, port 8002, variables d'environnement |

---

## Dépannage

### Pas d'événements dans Elasticsearch

1. **Vérifier que Logstash reçoit les webhooks** :
   ```bash
   docker logs ${ELK_PROJECT}-logstash --tail 100
   ```

2. **Tester l'endpoint manuellement** :
   ```bash
   curl -X POST -u "LOGSTASH_HTTP_USER:LOGSTASH_HTTP_PASSWORD" \
     -H "Content-Type: application/json" \
     -d '{"workflow_run":{"id":1,"run_attempt":1,"status":"completed","conclusion":"success"}}' \
     http://127.0.0.1:8002/
   ```

3. **Vérifier l'index** :
   ```bash
   docker exec ${ELK_PROJECT}-elasticsearch curl -s -u "elastic:$ELASTIC_PASSWORD" \
     "http://localhost:9200/_cat/indices/micro-crm-github-actions-*?v"
   ```

### Nginx : proxy vers Logstash

Si vous exposez via Nginx (ex. `https://ocr-ja7-elk.buyakov.com/githubhook`), ajouter dans la config Nginx :

```nginx
location /githubhook {
    proxy_pass http://127.0.0.1:8002;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

---

## Ressources

- [GitHub Webhooks – Workflow runs](https://docs.github.com/en/webhooks/webhook-events-and-payloads#workflow_run)
- [Logstash HTTP input plugin](https://www.elastic.co/guide/en/logstash/current/plugins-inputs-http.html)
