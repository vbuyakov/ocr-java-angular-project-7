# Pipeline CD – Publication des images Docker

Ce document décrit le pipeline de déploiement continu (CD) qui publie les images Docker du projet Orion MicroCRM vers **GitHub Container Registry** (ghcr.io).

---

## 1. Vue d’ensemble

| Élément | Détail |
|--------|--------|
| **Fichier** | `.github/workflows/docker-image.yml` |
| **Déclencheurs** | Push et Pull Request sur `main`, `workflow_dispatch` |
| **Registre** | GitHub Container Registry (`ghcr.io`) |
| **Objectif** | Valider que les images se construisent, et publier vers GHCR sur push `main` |

Le pipeline CD est **séparé** du pipeline CI (`ci.yml`). La CI exécute les tests et les builds applicatifs ; la CD gère la construction et la publication des images Docker.

---

## 2. Jobs et commandes

### 2.1 Job `build` (validation des images)

| Étape | Objectif | Où défini | Quand exécutée |
|-------|----------|-----------|----------------|
| `Set up Docker Buildx` | Activer le driver Buildx pour les builds multi-plateforme et le cache | `docker/setup-buildx-action@v3` | À chaque run |
| `Build backend image` | Construire l’image du backend Spring Boot | `docker/build-push-action`, `back/Dockerfile` | Push et PR sur `main` |
| `Build frontend image` | Construire l’image Angular (Caddy) | `docker/build-push-action`, `front/Dockerfile` | Push et PR sur `main` |

**Objectif** : Vérifier que les deux Dockerfiles se construisent correctement. Aucune image n’est poussée (push). Utilisation du cache GitHub Actions (`cache-from` / `cache-to`) pour accélérer les builds. L'image nginx n’est pas construite (docker-compose utilise `nginx:alpine`).

### 2.2 Job `publish` (publication GHCR)

| Étape | Objectif | Où défini | Quand exécutée |
|-------|----------|-----------|----------------|
| `Log in to GitHub Container Registry` | Authentification pour pousser les images | `docker/login-action@v3` | Uniquement sur push `main` |
| `Build and push backend/frontend` | Construire puis pousser chaque image | `docker/build-push-action` | Uniquement sur push `main` |

**Conditions** : `publish` ne s’exécute que si :
- L’événement est un **push** (pas une PR),
- La branche est **main**,
- Le job `build` a réussi.

**Tags utilisés** pour chaque image :
- `ghcr.io/{owner}/{repo}-{service}:{sha}` – traçabilité du commit
- `ghcr.io/{owner}/{repo}-{service}:latest` – version la plus récente

---

## 3. Authentification GHCR (aucun secret à configurer)

Le pipeline utilise le **`GITHUB_TOKEN`** fourni automatiquement par GitHub Actions. Aucun secret supplémentaire n'est requis pour publier vers GHCR. Pour le deploy (voir section 5), les secrets `PROD_HOST`, `PROD_SSH_USER` et `PROD_SSH_KEY` sont nécessaires.

| Élément | Valeur |
|---------|--------|
| `username` | `${{ github.actor }}` |
| `password` | `${{ secrets.GITHUB_TOKEN }}` |
| `registry` | `ghcr.io` |

**Permissions** : le job `publish` demande `packages: write` pour pouvoir pousser les images.

---

## 4. Images publiées

| Image | Dockerfile | Contexte |
|-------|------------|----------|
| `ghcr.io/{owner}/{repo}-back` | `back/Dockerfile` | `.` (racine du projet) |
| `ghcr.io/{owner}/{repo}-front` | `front/Dockerfile` | `.` (racine du projet) |

`{owner}` = organisation ou utilisateur GitHub. `{repo}` = nom du dépôt. L'image nginx n'est pas publiée (docker-compose utilise `nginx:alpine`).

**Note** : Le workflow ne s'exécute que sur tag `v*` (créé par semantic-release) ou `workflow_dispatch`. Aucune exécution sur push/PR pour limiter l'usage des Actions (free tier).

---

## 5. Ordre d’exécution

```
Release success / tag v* / workflow_dispatch
       │
       ▼
┌──────────────┐
│ Job: publish │  ← Login GHCR, build + push des 2 images
└──────────────┘
       │
       ▼
┌──────────────┐
│ Job: deploy  │  ← SSH → git pull → prod-up.sh --app-only (app uniquement, pas ELK)
└──────────────┘
```

Le pipeline CD est **indépendant** du pipeline CI. Les deux s’exécutent en parallèle lors d’un push sur `main`. Pour garantir que seuls des builds testés sont publiés, il est recommandé de :
- Protéger la branche `main` avec des status checks obligatoires (tests CI),
- Ne merger que des PR dont la CI est verte.

---

## 5. Deploy (app only, sans ELK) – automatique

Le job `deploy` s'exécute **automatiquement** après le job `publish` (build et push des images). Il ne s'exécute que lorsque `publish` a réussi, c'est-à-dire :

- après succès de **Release** sur `main`
- après push d'un tag `v*`
- après exécution manuelle du workflow (**Actions** → **Docker Image CI** → **Run workflow**)

---

Après publication des images, le job `deploy` se connecte en SSH au serveur et :
1. fait un `git pull` dans le répertoire de l'app
2. exécute `./misc/cicd/prod-up.sh --app-only` (pull images, redémarrage de l'app uniquement)

### Paramètres à ajouter dans GitHub

Aller dans le dépôt → **Settings** → **Secrets and variables** → **Actions**.

#### Variables (onglet « Variables »)

| Nom | Valeur | Requis |
|-----|--------|--------|
| `PROD_APP_PATH` | `/srv/www/ocr-education/ocr-java-angular-project-7` | Oui |

#### Secrets (onglet « Secrets »)

| Nom | Valeur | Requis |
|-----|--------|--------|
| `PROD_HOST` | Hostname ou IP du serveur (ex. `ocr-ja7.buyakov.com` ou `192.168.1.10`) | Oui |
| `PROD_SSH_USER` | Utilisateur SSH (ex. `deploy`, `ubuntu`, `root`) | Oui |
| `PROD_SSH_KEY` | **Clé privée** (pas le fichier `.pub`). Voir ci-dessous. | Oui |

**Format de `PROD_SSH_KEY`** — doit être la clé **privée** au format PEM :

- Fichier à copier : `~/.ssh/id_rsa` (ou `id_ed25519`), **pas** `id_rsa.pub`
- Contenu attendu : tout le bloc, de `-----BEGIN ... PRIVATE KEY-----` jusqu'à `-----END ... PRIVATE KEY-----`
- Sans mot de passe (passphrase) — sinon l'authentification échouera
- Pas d'espaces ou de lignes en trop au début ou à la fin

Pour générer une clé dédiée sans passphrase :

```bash
ssh-keygen -t ed25519 -C "deploy" -f ~/.ssh/deploy_key -N ""
# Ajouter ~/.ssh/deploy_key.pub sur le serveur (authorized_keys)
# Mettre le contenu de ~/.ssh/deploy_key dans PROD_SSH_KEY
```

Sans ces trois secrets, le job `deploy` échouera. Pour désactiver le déploiement, retirer ces secrets.

---

## 6. Références

- [Docker build-push-action](https://github.com/docker/build-push-action)
- [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
