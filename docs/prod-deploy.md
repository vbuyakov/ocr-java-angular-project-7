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
