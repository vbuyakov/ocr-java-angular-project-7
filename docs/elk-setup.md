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
   ├── Logstash (optionnel, inutilisé)
   └── Filebeat → Elasticsearch (direct, index ocr-ja7-logs-*)
```

- **Kibana** : seul service exposé (localhost:5601), accès via Nginx
- **Elasticsearch** : interne, non exposé
- **Filebeat** : collecte les logs orion-microcrm, envoie directement vers ES

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
| `misc/elk/filebeat.yml` | Collecte des logs nginx (orion-microcrm) via volume partagé |
| `misc/elk/logstash.conf` | Pipeline Filebeat → ES |
| `misc/elk/nginx-ocr-ja7-elk.conf` | Snippet Nginx (hôte) pour Kibana |

---

## Démarrage

**Ordre de démarrage** : lancer l’app avant l’ELK pour créer le volume `nginx-logs`.

**Option 1 – Script tout-en-un (app + ELK)** :

```bash
./misc/cicd/prod-up.sh --elk-only   # ELK seul
./misc/cicd/prod-up.sh             # App + ELK
```

**Option 2 – Compose manuel** :

```bash
# 1. Démarrer l'app (crée le volume nginx-logs)
docker compose up -d

# 2. Démarrer l'ELK
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

2. **Adapter `proxy_pass` au bon port** : le port doit correspondre à `KIBANA_PORT` utilisé par le compose (ex. 8001 ou 5601). Éditer `/etc/nginx/sites-available/ocr-ja7-elk` et modifier la ligne `proxy_pass http://127.0.0.1:XXXX;`.

3. Adapter les chemins des certificats SSL (Let's Encrypt ou existants).

4. Tester et recharger :

```bash
sudo nginx -t && sudo nginx -s reload
```

### 502 Bad Gateway – diagnostic

Sur le serveur, exécuter :

```bash
# 1. Vérifier sur quel port Kibana écoute
docker compose -f docker-compose-elk.yml ps
# Exemple : 127.0.0.1:8001->5601/tcp → Kibana sur 8001

# 2. Tester Kibana directement (sur le serveur)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8001
# 200 = OK. Si "Connection refused", Kibana n'écoute pas ou mauvais port.

# 3. Vérifier le port dans la config Nginx
grep proxy_pass /etc/nginx/sites-available/ocr-ja7-elk
# Doit afficher le même port (8001 ou 5601)

# 4. Logs Nginx (erreur connexion upstream)
sudo tail -20 /var/log/nginx/error.log
```

Si `curl http://127.0.0.1:8001` renvoie 200 mais le site en HTTPS donne 502, le port dans `proxy_pass` est probablement incorrect.

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

**Note :** Filebeat lit les logs nginx depuis un volume partagé (`nginx-logs`). Les premiers logs peuvent prendre 1–2 minutes à apparaître. Filtrer par `container: orion-microcrm-nginx` dans Kibana.

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

## Dépannage : pas de logs dans Kibana

### 1. Vérifier que l’ELK tourne sur le même hôte que l’app

Filebeat lit les logs dans `/var/lib/docker/containers/` sur l’hôte. L’ELK et l’app doivent tourner sur la même machine.

```bash
# ELK tourne ?
docker compose -f docker-compose-elk.yml ps

# Si absent : démarrer ELK
./misc/cicd/prod-up.sh --elk-only
# ou
docker compose -f docker-compose-elk.yml up -d
```

### 2. Vérifier qu’Elasticsearch indexe bien les logs

```bash
# Lister les index ocr-ja7-logs-*
docker exec ocr-ja7-elasticsearch curl -s -u "elastic:$ELASTIC_PASSWORD" \
  "http://localhost:9200/_cat/indices/ocr-ja7-logs-*?v"

# Compter les documents dans l’index du jour
docker exec ocr-ja7-elasticsearch curl -s -u "elastic:$ELASTIC_PASSWORD" \
  "http://localhost:9200/ocr-ja7-logs-$(date +%Y.%m.%d)/_count"
```

### 3. Vérifier Filebeat (logs nginx)

Filebeat lit les logs nginx depuis le volume partagé.

```bash
# Logs Filebeat
docker logs ocr-ja7-filebeat --tail 100

# Vérifier que le volume nginx-logs existe
docker volume ls | grep nginx-logs
```

### 4. Vérifier les logs bruts des conteneurs app

```bash
# Back (Spring Boot) – logs sur stdout
docker logs orion-microcrm-back-1 --tail 20

# Front (Caddy)
docker logs orion-microcrm-front-1 --tail 20

# Nginx
docker logs orion-microcrm-nginx-1 --tail 20
```

### 5. Vérifier Logstash

```bash
docker logs ocr-ja7-logstash --tail 50
```

### 6. Kibana : index pattern et plage horaire

1. **Créer la data view** : Stack Management → Data Views → Create → Index pattern : `ocr-ja7-logs-*` → Time field : `@timestamp` → Save.
2. **Plage horaire** : Discover → Last 15 minutes (ou Last 24 hours) → Refresh.
3. **Filtres** : `container: orion-microcrm-nginx` pour les logs nginx.

### 7. Volume nginx-logs

Filebeat lit les logs depuis le volume partagé `ocr-ja7-nginx-logs`, pas depuis `/var/lib/docker/containers`. L'app doit être démarrée en premier pour créer ce volume.

---

## Ressources

- Elasticsearch : 1 Go heap (`-Xms1g -Xmx1g`)
- Logstash : 256 Mo
- Prévoir ~4 Go RAM disponibles sur l’hôte
