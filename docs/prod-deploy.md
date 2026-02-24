# Déploiement en production

Ce document décrit le déploiement complet de l’application et de la stack ELK sur le serveur de production.

---

## Multi-projets (plusieurs ELK sur le même serveur)

Pour éviter les conflits de ports entre ELK de différents projets :

```bash
# Projet A (ocr-ja7) – défaut
./misc/cicd/prod-up.sh --elk-only

# Projet B – port Kibana 5602, nom distinct
ELK_PROJECT=autre-app KIBANA_PORT=5602 ./misc/cicd/prod-up.sh --elk-only
```

Chaque projet doit avoir son propre `ELK_PROJECT` et `KIBANA_PORT`. Dans Nginx, pointer `proxy_pass` vers le bon port (5601, 5602, etc.).

---

## Déploiement via CI/CD (automatique)

Le workflow `docker-image.yml` déploie automatiquement après la publication des images. Le job `deploy` se connecte en SSH, exécute `git pull` puis `./misc/cicd/prod-up.sh --app-only` (app uniquement, sans ELK).

**Paramètres à configurer** (Settings → Secrets and variables → Actions) : variables `PROD_APP_PATH`, secrets `PROD_HOST`, `PROD_SSH_USER`, `PROD_SSH_KEY`. Détails dans [cd-setup.md](cd-setup.md).

---

## Prérequis

- Docker et Docker Compose installés
  - Si `docker compose` échoue avec « unknown shorthand flag: 'f' » : `sudo apt install docker-compose-plugin`
- Accès au registre GHCR (token GitHub avec `read:packages`)
- Nginx installé sur l’hôte pour SSL et routage des domaines
- ~4 Go RAM disponibles pour ELK
- ELK : `ELASTIC_PASSWORD` dans `.env`

---

## Domaines

| Domaine | Service |
|---------|---------|
| `ocr-ja7.buyakov.com` | Application (front + back) |
| `ocr-ja7-elk.buyakov.com` | Kibana (logs) |

---

## Démarrage rapide

```bash
# Connexion GHCR (une fois)
# Token : GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
# Scope requis : read:packages
echo YOUR_TOKEN | docker login ghcr.io -u vbuyakov --password-stdin

# Démarrer app + ELK
./misc/cicd/prod-up.sh
```

Options du script :

| Commande | Effet |
|----------|-------|
| `./misc/cicd/prod-up.sh` | App + ELK (pull images) |
| `./misc/cicd/prod-up.sh --app-only` | Application uniquement |
| `./misc/cicd/prod-up.sh --elk-only` | Stack ELK uniquement |
| `./misc/cicd/prod-up.sh --restart` | Redémarrer sans pull (appliquer changements config) |

---

## Étapes détaillées

### 1. Préparation des images

```bash
echo YOUR_TOKEN | docker login ghcr.io -u vbuyakov --password-stdin
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
```

Pour figer une version (ex. v1.0.1) :

```bash
export BACK_IMAGE=ghcr.io/vbuyakov/ocr-java-angular-project-7-back:v1.0.1
export FRONT_IMAGE=ghcr.io/vbuyakov/ocr-java-angular-project-7-front:v1.0.1
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
```

### 2. Lancement de l’application

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build
```

### 3. Lancement de la stack ELK

```bash
docker compose -f docker-compose-elk.yml up -d
```

### 4. Vérifications

```bash
# App
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps

# ELK
docker compose -f docker-compose-elk.yml ps
curl -s http://localhost:9200/_cluster/health
```

---

## Certificats SSL (Let's Encrypt)

### Prérequis

- Les domaines `ocr-ja7.buyakov.com` et `ocr-ja7-elk.buyakov.com` pointent vers l'IP du serveur (DNS A)
- Le port 80 est accessible depuis internet (validation HTTP)

### Installation Certbot

```bash
# Debian / Ubuntu
sudo apt update
sudo apt install certbot

# Ou via snap
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
```

### Génération des certificats

**Mode standalone** (arrêter Nginx avant) :

```bash
sudo systemctl stop nginx

# App
sudo certbot certonly --standalone -d ocr-ja7.buyakov.com

# ELK
sudo certbot certonly --standalone -d ocr-ja7-elk.buyakov.com

sudo systemctl start nginx
```

**Mode webroot** (Nginx actif) :

```bash
# Un seul répertoire pour tous les domaines/projets
sudo mkdir -p /var/www/certbot
# Configurer location /.well-known/acme-challenge/ { root /var/www/certbot; } dans Nginx

sudo certbot certonly --webroot -w /var/www/certbot -d ocr-ja7.buyakov.com
sudo certbot certonly --webroot -w /var/www/certbot -d ocr-ja7-elk.buyakov.com
```

Certificats : `/etc/letsencrypt/live/<domain>/fullchain.pem`, `privkey.pem`

### Renouvellement automatique

```bash
sudo certbot renew --dry-run
# Cron : 0 3 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
```

---

## Configuration Nginx (hôte)

L’hôte Nginx termine le SSL et achemine vers :
- **ocr-ja7.buyakov.com** → app (127.0.0.1:8080)
- **ocr-ja7-elk.buyakov.com** → Kibana (127.0.0.1:5601)

### Fichiers et installation

| Fichier | Domaine | Backend |
|---------|---------|---------|
| `misc/docker/nginx-ocr-ja7.conf` | ocr-ja7.buyakov.com | 127.0.0.1:8080 |
| `misc/elk/nginx-ocr-ja7-elk.conf` | ocr-ja7-elk.buyakov.com | 127.0.0.1:5601 |

**Étapes :**

1. Installer Nginx

```bash
sudo apt install nginx
```

2. Créer le répertoire Certbot

```bash
sudo mkdir -p /var/www/certbot
```

3. Copier les configurations (depuis la racine du projet)

```bash
sudo cp misc/docker/nginx-ocr-ja7.conf /etc/nginx/sites-available/ocr-ja7
sudo cp misc/elk/nginx-ocr-ja7-elk.conf /etc/nginx/sites-available/ocr-ja7-elk
```

4. Activer les sites

```bash
sudo ln -sf /etc/nginx/sites-available/ocr-ja7 /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/ocr-ja7-elk /etc/nginx/sites-enabled/
```

5. Obtenir les certificats SSL (voir section Certificats SSL ci-dessus)

6. Définir `APP_PORT=8080` dans `.env` pour éviter conflit avec Nginx

```bash
# Ajouter ou modifier dans .env
APP_PORT=8080
```

7. Tester et recharger Nginx

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## Documents associés

| Document | Contenu |
|----------|---------|
| [docker.md](docker.md) | Docker, dev vs prod, variables |
| [elk-setup.md](elk-setup.md) | Détails ELK, index, Kibana |
| [cd-setup.md](cd-setup.md) | GHCR, publication des images |

---

## Plan de sauvegarde des données

### Périmètre

| Donnée | Emplacement | Criticité |
|--------|-------------|-----------|
| **Base de données applicative** | Volume Docker `microcrm-data` (H2 fichier ou PostgreSQL) | Haute |
| **Configuration** | Fichier `.env` à la racine du projet | Haute |
| **Certificats SSL** | `/etc/letsencrypt/live/` | Haute |
| **Index Elasticsearch** | Volume Docker `ocr-ja7-esdata` | Basse (logs reconstructibles) |
| **Configuration Nginx** | `/etc/nginx/sites-available/` | Moyenne |

> **Prérequis** : la base de données doit être configurée en mode fichier persistant (`jdbc:h2:file:/data/microcrm`) ou PostgreSQL avec un volume Docker nommé. Avec H2 en mémoire (configuration par défaut), aucune sauvegarde des données applicatives n'est possible.

---

### Sauvegarde automatisée (cron)

Le script suivant est déposé sur le serveur de production dans `/opt/scripts/backup-microcrm.sh` et exécuté automatiquement chaque nuit.

**Script `/opt/scripts/backup-microcrm.sh` :**

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/backups/microcrm"
DATE=$(date +%Y-%m-%d_%H-%M)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

# 1. Sauvegarde du volume de base de données
docker run --rm \
  -v microcrm-data:/data:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/db-$DATE.tar.gz" -C /data .

# 2. Sauvegarde de la configuration
cp /opt/app/microcrm/.env "$BACKUP_DIR/env-$DATE.bak"

# 3. Sauvegarde des certificats SSL
tar czf "$BACKUP_DIR/ssl-$DATE.tar.gz" /etc/letsencrypt/live/ 2>/dev/null || true

# 4. Purge des sauvegardes de plus de RETENTION_DAYS jours
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Sauvegarde terminée : $BACKUP_DIR/db-$DATE.tar.gz"
```

**Installation du cron :**

```bash
# Rendre le script exécutable
sudo chmod +x /opt/scripts/backup-microcrm.sh

# Ajouter la tâche cron (sauvegarde chaque nuit à 02h00)
sudo crontab -e
# Ajouter la ligne :
# 0 2 * * * /opt/scripts/backup-microcrm.sh >> /var/log/microcrm-backup.log 2>&1
```

**Vérification des sauvegardes :**

```bash
# Lister les sauvegardes disponibles
ls -lh /opt/backups/microcrm/

# Vérifier l'intégrité d'une archive
tar tzf /opt/backups/microcrm/db-2026-02-24_02-00.tar.gz
```

---

### Procédure de restauration automatisée

La restauration peut être déclenchée manuellement ou intégrée dans un script de rollback post-déploiement.

**Script `/opt/scripts/restore-microcrm.sh` :**

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/backups/microcrm"

# Utiliser la dernière sauvegarde si aucun fichier n'est passé en argument
BACKUP_FILE="${1:-$(ls -t "$BACKUP_DIR"/db-*.tar.gz | head -1)}"

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
  echo "ERREUR : aucune sauvegarde trouvée dans $BACKUP_DIR"
  exit 1
fi

echo "Restauration depuis : $BACKUP_FILE"

# 1. Arrêter l'application (back uniquement, nginx reste actif)
cd /opt/app/microcrm
docker compose -f docker-compose.yml -f docker-compose.prod.yml stop back

# 2. Vider le volume et restaurer les données
docker run --rm \
  -v microcrm-data:/data \
  -v "$BACKUP_DIR":/backup:ro \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$BACKUP_FILE") -C /data"

# 3. Redémarrer l'application
docker compose -f docker-compose.yml -f docker-compose.prod.yml start back

# 4. Smoke test post-restauration
sleep 10
if curl -sf http://localhost:8080/actuator/health > /dev/null; then
  echo "Restauration réussie. Application opérationnelle."
else
  echo "ATTENTION : smoke test échoué après restauration. Vérifier les logs."
  docker logs orion-microcrm-back-1 --tail 30
  exit 1
fi
```

**Utilisation :**

```bash
# Restaurer depuis la dernière sauvegarde automatiquement
sudo /opt/scripts/restore-microcrm.sh

# Restaurer depuis une archive spécifique
sudo /opt/scripts/restore-microcrm.sh /opt/backups/microcrm/db-2026-02-20_02-00.tar.gz
```

**Test hebdomadaire de la restauration (automatisé) :**

```bash
# Cron test de restauration chaque dimanche à 03h00 (hors heures de pointe)
# 0 3 * * 0 /opt/scripts/restore-microcrm.sh >> /var/log/microcrm-restore-test.log 2>&1
```

> Ce test hebdomadaire valide que la sauvegarde est fonctionnelle et que la procédure de restauration ne régresse pas entre les mises à jour.

---

### Sauvegarde distante (recommandation)

Pour éviter la perte des sauvegardes en cas de défaillance du serveur, copier les archives vers un stockage distant :

```bash
# Exemple : copie vers un second serveur via rsync (à ajouter à backup-microcrm.sh)
rsync -az "$BACKUP_DIR/" user@backup-server:/backups/microcrm/

# Exemple : copie vers S3-compatible (rclone)
rclone copy "$BACKUP_DIR/" s3:bucket-name/microcrm-backups/
```

---

## Plan des mises à jour

### Vue d'ensemble

Les mises à jour couvrent trois périmètres distincts, avec des fréquences et responsabilités différentes.

| Périmètre | Fréquence | Déclencheur | Responsable |
|-----------|-----------|-------------|-------------|
| **Application** (code métier) | Continu | Pipeline CD automatique | GitHub Actions |
| **Dépendances** (npm, Gradle, images Docker) | Mensuel | Revue manuelle ou Dependabot | Développeur |
| **Infrastructure** (OS, Docker, Nginx, certificats) | Trimestriel | Cron / planification | Administrateur serveur |

---

### Mises à jour applicatives (automatisées)

Le pipeline CD assure les mises à jour applicatives sans intervention manuelle :

```
Push main → CI (tests + SonarQube) → Release (semantic-release) → Docker Image → Deploy SSH
```

**Validation post-déploiement** (à ajouter dans `docker-image.yml`) :

```yaml
- name: Smoke test post-déploiement
  uses: appleboy/ssh-action@v1
  with:
    host: ${{ secrets.PROD_HOST }}
    username: ${{ secrets.PROD_SSH_USER }}
    key: ${{ secrets.PROD_SSH_KEY }}
    script: |
      sleep 15
      curl -f http://localhost:8080/actuator/health || exit 1
```

**Rollback en cas d'échec** :

```bash
# Revenir à la version précédente (image taguée dans GHCR)
export BACK_IMAGE=ghcr.io/vbuyakov/ocr-java-angular-project-7-back:v1.1.0
export FRONT_IMAGE=ghcr.io/vbuyakov/ocr-java-angular-project-7-front:v1.1.0
./misc/cicd/prod-up.sh --app-only
```

---

### Mises à jour des dépendances (mensuel)

**Backend (Gradle) :**

```bash
# Lister les dépendances obsolètes
cd back && ./gradlew dependencyUpdates

# Mettre à jour Spring Boot (modifier build.gradle)
# Vérifier les breaking changes dans les release notes avant mise à jour majeure
```

**Frontend (npm) :**

```bash
# Lister les dépendances obsolètes
cd front && npm outdated

# Mettre à jour les dépendances mineures/patch de manière sécurisée
npm update

# Mise à jour Angular (majeure) — suivre le guide officiel ng update
npx ng update @angular/core @angular/cli
```

**Images Docker de base :**

Vérifier périodiquement les nouvelles versions des images de base utilisées dans les Dockerfiles :
- `eclipse-temurin:17-jdk-alpine` (backend)
- `caddy:alpine` (frontend)
- `nginx:alpine` (reverse proxy)

Mettre à jour les tags et rebuilder les images via le pipeline CI.

---

### Mises à jour infrastructure (trimestriel)

**Système d'exploitation et Docker :**

```bash
# Mise à jour du système (Debian/Ubuntu)
sudo apt update && sudo apt upgrade -y

# Mise à jour Docker Engine
sudo apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Vérifier la version Docker après mise à jour
docker --version && docker compose version
```

**Certificats SSL (automatique) :**

Le renouvellement Let's Encrypt est automatisé via cron (voir section Certificats SSL). Vérifier manuellement la date d'expiration si nécessaire :

```bash
sudo certbot certificates
# Ou tester le renouvellement à blanc
sudo certbot renew --dry-run
```

**Nginx :**

```bash
# Mettre à jour Nginx
sudo apt install nginx

# Après mise à jour, tester la configuration
sudo nginx -t && sudo systemctl reload nginx
```

---

### Ajustement régulier des processus

Les processus de déploiement et de mise à jour doivent être réévalués à intervalles réguliers pour rester adaptés à l'évolution du projet.

**Revue mensuelle (après chaque release) :**

| Point de revue | Action |
|----------------|--------|
| Durée du pipeline CI/CD | Si > 15 min : identifier les étapes lentes et optimiser (cache Gradle/npm, parallélisation) |
| CFR (Change Failure Rate) | Si > 15% : renforcer les tests ou le staging avant prod |
| Logs des sauvegardes | Vérifier `/var/log/microcrm-backup.log` : aucune erreur, taille cohérente des archives |
| Alertes Kibana | Réviser les seuils si trop de faux positifs ou alertes manquées |

**Revue trimestrielle :**

| Point de revue | Action |
|----------------|--------|
| Métriques DORA | Comparer avec le trimestre précédent (voir [kpi-dora-analysis.md](kpi-dora-analysis.md)) |
| Dette technique | Réévaluer les priorités du tableau de dette (voir [technical-debt.md](technical-debt.md)) |
| Stratégie de sauvegarde | Adapter la rétention (30 jours) et la fréquence en fonction du volume de données |
| Dépendances majeures | Planifier les mises à jour majeures (Spring Boot, Angular) avec tests de non-régression |
| Capacité serveur | Vérifier RAM (ELK ~4 Go), disque (index Elasticsearch, sauvegardes), et anticiper le scaling |

**Mise à jour de cette documentation :**

Ce document doit être mis à jour à chaque modification significative de l'infrastructure ou des processus. La date de dernière révision doit être reflétée dans le commit qui l'accompagne.
