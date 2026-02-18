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
- **Filebeat** : collecte uniquement les logs du projet orion-microcrm (autodiscover, pas tout le serveur)

---

## Multi-projets (éviter les conflits de ports)

Sur un serveur avec plusieurs ELK (un par projet), définir pour chaque projet :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `ELK_PROJECT` | `ocr-ja7` | Préfixe des conteneurs et réseaux |
| `KIBANA_PORT` | `5601` | Port hôte pour Kibana |
| `ELASTIC_PASSWORD` | — | Mot de passe (elastic, kibana_system). Connexion Kibana : `elastic` |

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

## Sécurité (built-in users)

- **Kibana** : `kibana_system`
- **Logstash** : `logstash_writer` (rôle dédié pour écrire dans `ocr-ja7-logs-*`)
- **Connexion Kibana** : `elastic` (superuser, uniquement pour l'UI)

`kibana-entrypoint.sh` configure les mots de passe au démarrage. Définir `ELASTIC_PASSWORD` dans `.env`. [Built-in users](https://www.elastic.co/guide/en/elasticsearch/reference/current/built-in-users.html)

---

## Fichiers

| Fichier | Rôle |
|---------|------|
| `docker-compose-elk.yml` | Compose ELK standalone |
| `misc/cicd/prod-up.sh` | Script de démarrage app + ELK en prod |
| `misc/elk/filebeat.yml` | Autodiscover : collecte uniquement les conteneurs orion-microcrm |
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

## Voir les logs dans Kibana

1. **Accéder à Kibana**  
   - En prod : https://ocr-ja7-elk.buyakov.com (via Nginx)  
   - En local : http://127.0.0.1:5601  

2. **Se connecter** avec l’utilisateur `elastic` et le mot de passe défini dans `ELASTIC_PASSWORD`.

3. **Créer l’index pattern** (première fois ou si absent) :  
   - Menu ☰ → **Stack Management** → **Index Patterns** (ou **Data Views**)  
   - **Create index pattern** / **Create data view**  
   - Nom de l’index : `ocr-ja7-logs-*`  
   - Champ temporel : `@timestamp` → **Save**

4. **Consulter les logs** :  
   - Menu ☰ → **Analytics** → **Discover**  
   - Choisir la data view `ocr-ja7-logs-*`  
   - Ajuster l’intervalle (ex. « Last 15 minutes ») et cliquer sur **Refresh**  
   - Filtrer par `docker.container.name` (back, front) ou `message`, etc.

**Note :** Filebeat ne récupère que les logs des conteneurs dont le nom contient `back` ou `front`. Les premiers logs peuvent prendre 1–2 minutes à apparaître.

---

## Index Elasticsearch

Index créé par Logstash : `ocr-ja7-logs-YYYY.MM.dd`

Pattern utilisé dans Kibana : `ocr-ja7-logs-*`

### Purge des anciens index (libérer des shards)

Sur un cluster partagé, supprimer les index de plus de 90 jours :

```bash
# Lister les index à supprimer (exemple : > 90 jours)
docker exec ocr-ja7-elasticsearch curl -s -u "elastic:$ELASTIC_PASSWORD" \
  "http://localhost:9200/_cat/indices/ocr-ja7-logs-*?h=index" | sort

# Supprimer les index d'une année (ex. 2022)
docker exec ocr-ja7-elasticsearch curl -X DELETE \
  -u "elastic:$ELASTIC_PASSWORD" \
  "http://localhost:9200/ocr-ja7-logs-2022.*"

# Supprimer les index avant une date (ex. avant 2025-06-01)
# Adapter la date selon besoin
docker exec ocr-ja7-elasticsearch curl -X DELETE \
  -u "elastic:$ELASTIC_PASSWORD" \
  "http://localhost:9200/ocr-ja7-logs-2022.10.*,ocr-ja7-logs-2022.11.*"
```

---

## Ressources

- Elasticsearch : 1 Go heap (`-Xms1g -Xmx1g`)
- Logstash : 256 Mo
- Prévoir ~4 Go RAM disponibles sur l’hôte
