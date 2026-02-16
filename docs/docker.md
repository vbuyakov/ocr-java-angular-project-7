# Docker – Configuration et bonnes pratiques

## Vue d’ensemble

L’application Orion MicroCRM est conteneurisée pour faciliter le déploiement et garantir une exécution homogène entre environnements. Ce document décrit les choix techniques des Dockerfiles et du fichier `docker-compose.yml`, ainsi que les bonnes pratiques de sécurité appliquées.

---

## Architecture des images

| Service | Image de build | Image d’exécution | Rôle |
|--------|----------------|-------------------|------|
| **back** | eclipse-temurin:17-jdk | eclipse-temurin:17-jre | API Spring Boot |
| **front** | node:20-alpine | alpine:3.19 + Caddy | Angular + reverse-proxy |
| **nginx** | — | nginx:alpine | Reverse-proxy principal |

---

## Choix des images de base

### Backend (Java)

- **eclipse-temurin:17-jdk** (build) et **eclipse-temurin:17-jre** (run)
  - **Temurin** : distribution OpenJDK maintenue par l’Eclipse Adoptium Project (ex-AdoptOpenJDK), largement utilisée en production.
  - **Debian** : support multi-plateforme (amd64, arm64), contrairement aux variantes Alpine limitées à amd64.
  - **JRE** en exécution : pas de JDK en production, image plus légère.

### Frontend (Angular + Caddy)

- **node:20-alpine** (build) : image Node officielle, LTS, minimale.
- **alpine:3.19** (run) : base légère avec **Caddy** pour servir les fichiers statiques et le reverse-proxy (alternative légère à nginx pour le front).

### Nginx

- **nginx:alpine** : image officielle Nginx sur Alpine, légère et sécurisée.

---

## Bonnes pratiques de sécurité

### 1. Utilisateur non-root (backend)

Le backend Spring Boot s’exécute avec un utilisateur non-root (`appuser` / `appgroup`) pour limiter les impacts en cas de compromission :

```dockerfile
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
COPY --from=build --chown=appuser:appgroup ...
USER appuser
```

### 2. Images minimales (slim / alpine)

Toutes les images sont basées sur **Alpine** pour :
- Réduire la surface d’attaque
- Limiter la taille des images
- Faciliter les mises à jour

### 3. Aucune donnée sensible dans les images

- Pas de mots de passe, clés API ou certificats hardcodés.
- Les secrets sont injectés via variables d’environnement ou fichiers montés (cf. `.env.example`).

### 4. Build multi-stage

- **back** et **front** utilisent un build multi-stage : outil de build (JDK / Node) uniquement en phase de build, image de production sans ces outils.
- Réduit la taille finale et les vulnérabilités liées aux outils de build.

### 5. Réduction du contexte de build (.dockerignore)

Le fichier `.dockerignore` exclut les répertoires inutiles (`.gradle`, `build`, `node_modules`, `dist`, etc.) pour :
- Accélérer le transfert de contexte vers le daemon Docker
- Éviter d’inclure des artefacts sensibles ou temporaires

---

## Orchestration avec Docker Compose

### Structure des services

```
┌─────────┐     ┌─────────┐     ┌────────────┐
│  nginx  │────▶│  front  │     │    back    │
│  :80    │     │ (Caddy) │     │  (Spring)  │
└─────────┘     └─────────┘     └────────────┘
      │                │                │
      └────────────────┴────────────────┘
                   orioncrm
```

- **nginx** : reverse-proxy principal, seul service exposé sur le port (`APP_PORT`, défaut 80).
- **front** : application Angular servie par Caddy.
- **back** : API Spring Boot, accessible uniquement via le réseau interne.

### Démarrage

**En développement** (build local à partir des Dockerfiles) :

```bash
# Build et démarrage
docker compose up -d

# Ou avec build explicite
docker compose build --no-cache
docker compose up -d
```

**En production** (images pré-construites depuis GHCR) :

```bash
# Connexion au registre (une fois, avec un PAT ayant read:packages)
docker login ghcr.io -u vbuyakov

# Démarrer app (et optionnellement ELK) via le script
./misc/cicd/prod-up.sh             # App + ELK
./misc/cicd/prod-up.sh --app-only  # App seul

# Ou manuellement
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build
```

Voir [prod-deploy.md](prod-deploy.md) pour le déploiement complet.

Pour figer une version en production (ex. `v1.0.1`) :

```bash
BACK_IMAGE=ghcr.io/vbuyakov/ocr-java-angular-project-7-back:v1.0.1 \
FRONT_IMAGE=ghcr.io/vbuyakov/ocr-java-angular-project-7-front:v1.0.1 \
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build
```

### Variables d’environnement

| Variable | Défaut | Description |
|----------|--------|-------------|
| `APP_PORT` | `80` | Port exposé pour nginx |
| `SPRING_APP_NAME` | `microcrm` | Nom de l’application Spring |
| `DOCKER_NETWORK` | `orion-microcrm_network` | Nom du réseau Docker |
| `DOCKER_NETWORK_EXTERNAL` | `false` | Si `true`, le réseau doit déjà exister |
| `BACK_IMAGE` | `ghcr.io/...-back:latest` | Image backend (prod overlay) |
| `FRONT_IMAGE` | `ghcr.io/...-front:latest` | Image frontend (prod overlay) |

---

## Analyse de sécurité des images (scanning)

Il est recommandé de scanner régulièrement les images Docker pour détecter les vulnérabilités.

### Outils possibles

- **Trivy** (open source) : `trivy image <image_name>`
- **Docker Scout** : `docker scout quickview <image_name>`
- **Twistlock / Prisma Cloud** : solution commerciale, intégration CI/CD
- **Snyk** : analyse de dépendances et conteneurs

### Exemple avec Trivy

```bash
# Scanner l’image backend
docker compose build back
trivy image orion-microcrm-back:latest

# Scanner toutes les images du projet
docker compose build
for img in orion-microcrm-back orion-microcrm-front orion-microcrm-nginx; do
  trivy image ${img}:latest
done
```

### Points de vigilance

- Utiliser des images à jour (Alpine, Temurin, Node).
- Vérifier les CVE régulièrement et mettre à jour les images de base.
- Ne pas utiliser d’images obsolètes ou non officielles.

---

## Références

- [Docker Docs – Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Eclipse Temurin](https://adoptium.net/)
- [Twistlock – Secure containerized applications](https://developer.ibm.com/articles/secure-containerized-applications-with-twistlock/)
