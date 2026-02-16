# Workflow de release – semantic-release

Ce document décrit le fonctionnement des releases automatiques du projet Orion MicroCRM, basées sur **semantic-release** et **Conventional Commits**.

---

## 1. Vue d’ensemble

| Élément | Détail |
|--------|--------|
| **Fichier workflow** | `.github/workflows/release.yml` |
| **Configuration** | `release.config.js` |
| **Déclencheur** | Push sur `main` uniquement |
| **Versioning** | SemVer (MAJOR.MINOR.PATCH) |

**Principe** : semantic-release analyse les commits sur `main` depuis la dernière release. Si des commits « releaseworthy » sont présents, il génère une nouvelle version, crée un tag Git, publie une release GitHub (notes générées automatiquement), met à jour `CHANGELOG.md`, puis le push du tag déclenche la publication des images Docker sur GHCR.

---

## 2. Règles de commit (Conventional Commits)

Pour qu’une release soit créée, les messages de commit doivent suivre le format [Conventional Commits](https://www.conventionalcommits.org/) :

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Types qui déclenchent une release

| Type | Bump | Exemple | Version |
|------|------|---------|---------|
| `feat` | **Minor** (1.0.0 → 1.1.0) | `feat(api): add export endpoint` | Nouvelle fonctionnalité |
| `fix` | **Patch** (1.0.0 → 1.0.1) | `fix(ui): correct button alignment` | Correction de bug |
| `perf` | **Patch** | `perf(api): optimize query` | Amélioration de performance |
| `feat!` ou `BREAKING CHANGE` | **Major** (1.0.0 → 2.0.0) | `feat!: remove legacy API` | Changement incompatible |

### Types qui ne déclenchent pas de release

| Type | Exemple |
|------|---------|
| `docs` | `docs: update README` |
| `chore` | `chore: update dependencies` |
| `style` | `style: fix lint` |
| `refactor` | `refactor: simplify service` |
| `test` | `test: add unit tests` |
| `ci` | `ci: fix workflow` |

### Format détaillé

- **Scope** (optionnel) : zone impactée, ex. `feat(api):`, `fix(front):`
- **Breaking change** : `feat!: ...` ou footer `BREAKING CHANGE: description`
- **Subject** : impératif, minuscules, pas de point final

**Exemples valides :**
```
feat: add person search
fix(ui): resolve navigation bug
feat(api)!: change response format
docs: update setup guide
chore(deps): upgrade Angular
```

---

## 3. Workflow Git et tags

### Déclenchement

- **Branche** : uniquement `main`
- **Événement** : Release s'exécute après succès de la CI sur `main` (ou `workflow_dispatch`)
- **Tag** : créé uniquement sur `main` après une release réussie

### Flux d’exécution

```
Push sur main
      │
      ▼
┌─────────────────────┐
│ Workflow: CI       │  ← Tests, build, SonarQube
└─────────────────────┘
      │ (si succès)
      ▼
┌─────────────────────┐
│ Workflow: Release   │
│ 1. semantic-release│
└─────────────────────┘
      │
      ├─► Analyse des commits (depuis dernier tag)
      │
      ├─► Si releaseworthy :
      │     • Nouvelle version (ex. v1.2.0)
      │     • Tag Git v1.2.0
      │     • Mise à jour CHANGELOG.md
      │     • Commit CHANGELOG [skip ci]
      │     • Release GitHub (notes auto)
      │     • Push du tag v1.2.0
      │
      │     ┌──────────────────────────────┐
      │     │ Workflow: Docker Image (tag)  │
      │     │ Build + push GHCR             │
      │     │ Tags : v1.2.0 et latest       │
      │     └──────────────────────────────┘
      │
      └─► Sinon : rien (pas de release, pas d'images)
```

### Réponses aux questions de design

| Question | Réponse |
|----------|---------|
| **Release candidate par commit ?** | Non. Une release (stable) est créée uniquement quand il existe des commits `feat`, `fix`, `perf` ou `BREAKING` depuis la dernière release. Les commits `docs`, `chore`, etc. n’induisent pas de nouvelle version. |
| **Action humaine requise ?** | Non. La Release attend que la CI soit verte, puis s'exécute automatiquement. Lancement manuel possible via `workflow_dispatch`. |
| **Branches différentes par release ?** | Non. Les tags (`v1.0.0`, `v1.1.0`) sont créés sur `main`. Pas de branches dédiées (`release/1.0`, etc.). |
| **Test release avant stable ?** | Pour une pre-release, on peut ajouter une branche `beta` ou `next` dans `release.config.js` (non configuré par défaut). |

---

## 4. Artefacts de release (images Docker)

Lorsqu’une release est créée, le workflow `docker-image.yml` est déclenché par le tag (ex. `v1.0.0`). Les images Docker sont alors publiées sur GHCR avec les tags :

| Image | Tags |
|-------|------|
| `ghcr.io/{owner}/{repo}-back` | `v1.0.0`, `latest` |
| `ghcr.io/{owner}/{repo}-front` | `v1.0.0`, `latest` |

Aucun artefact JAR ou ZIP n’est publié ; les images Docker constituent le résultat de la release.

---

## 5. Première release

Pour créer la première release (v1.0.0) :

1. S’assurer que `main` contient au moins un commit `feat` ou `fix`
2. Pousser sur `main` (ou merger une PR)
3. Le workflow Release s’exécutera et créera la v1.0.0 si des commits releaseworthy existent

**Note** : avant le premier tag, semantic-release considère l’ensemble des commits depuis la création du dépôt. Un dépôt neuf avec seulement des `chore` ou `docs` n’aura pas de release tant qu’il n’y aura pas de `feat` ou `fix`.

---

## 6. Dépannage

| Problème | Cause | Solution |
|----------|-------|----------|
| **Docker Image ne se lance pas** | Le workflow ne se déclenche que sur push de tag `v*`. Si semantic-release ne crée pas de release (pas de `feat`/`fix`), aucun tag. | S'assurer que les commits sur `main` incluent au moins un `feat` ou `fix`. Les merge commits ne comptent pas. |
| **Release ne s'exécute pas** | Release attend que la CI soit verte. | Corriger les échecs de la CI. |
| **Pas de release malgré des feat** | semantic-release analyse depuis le dernier tag. | Vérifier l'onglet Releases sur GitHub. |

---

## 7. Références

- [semantic-release](https://github.com/semantic-release/semantic-release)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)
