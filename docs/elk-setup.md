# ELK Stack – Déploiement en production

Stack ELK pour centraliser les logs du backend (Spring Boot) et du frontend (Caddy) via Kibana.

Pour le déploiement complet (app + ELK), voir [prod-deploy.md](prod-deploy.md).

---

## Architecture

```
Host Nginx (SSL) → ocr-ja7-elk.buyakov.com
       │
       ▼
   Kibana :5601 (localhost uniquement)
       │
   Réseau Docker elk
       │
   ├── Elasticsearch (interne)
   ├── Logstash (interne)
   └── Filebeat ← /var/lib/docker/containers (back, front)
```

- **Kibana** : seul service exposé (localhost:5601), accès via Nginx
- **Elasticsearch** : interne, non exposé
- **Logstash** : interne, reçoit Filebeat sur 5044
- **Filebeat** : collecte les logs des conteneurs back et front

---

## Multi-projets (éviter les conflits de ports)

Sur un serveur avec plusieurs ELK (un par projet), définir pour chaque projet :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `ELK_PROJECT` | `ocr-ja7` | Préfixe des conteneurs et réseaux |
| `KIBANA_PORT` | `5601` | Port hôte pour Kibana |

Exemple pour le 2ᵉ projet :

```bash
ELK_PROJECT=autre-projet KIBANA_PORT=5602 docker compose -f docker-compose-elk.yml up -d
```

Ou via fichier `.env` à la racine du projet :

```
ELK_PROJECT=autre-projet
KIBANA_PORT=5602
```

Adapter dans Nginx : `proxy_pass http://127.0.0.1:5602`.

---

## Fichiers

| Fichier | Rôle |
|---------|------|
| `docker-compose-elk.yml` | Compose ELK standalone |
| `misc/cicd/prod-up.sh` | Script de démarrage app + ELK en prod |
| `misc/elk/filebeat.yml` | Collecte des logs Docker |
| `misc/elk/logstash.conf` | Pipeline Filebeat → ES |
| `misc/elk/nginx-ocr-ja7-elk.conf` | Snippet Nginx (hôte) pour Kibana |

---

## Démarrage

**Option 1 – Script tout-en-un (app + ELK)** :

```bash
./misc/cicd/prod-up.sh --elk-only   # ELK seul
./misc/cicd/prod-up.sh             # App + ELK
```

**Option 2 – Compose manuel** :

```bash
docker compose -f docker-compose-elk.yml up -d
```

Vérification :

```bash
docker compose -f docker-compose-elk.yml ps
curl -s http://localhost:9200/_cluster/health   # Elasticsearch
```

---

## Configuration Nginx (hôte)

1. Copier le snippet dans la config Nginx :

```bash
sudo cp misc/elk/nginx-ocr-ja7-elk.conf /etc/nginx/sites-available/ocr-ja7-elk
sudo ln -s /etc/nginx/sites-available/ocr-ja7-elk /etc/nginx/sites-enabled/
```

2. Adapter les chemins des certificats SSL (Let's Encrypt ou existants).

3. Tester et recharger :

```bash
sudo nginx -t && sudo nginx -s reload
```

---

## Index Elasticsearch

Index créé par Logstash : `ocr-ja7-logs-YYYY.MM.dd`

Dans Kibana, créer un index pattern : `ocr-ja7-logs-*`

---

## Ressources

- Elasticsearch : 1 Go heap (`-Xms1g -Xmx1g`)
- Logstash : 256 Mo
- Prévoir ~4 Go RAM disponibles sur l’hôte
