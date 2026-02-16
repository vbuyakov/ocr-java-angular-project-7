# Plan d'automatisation - Orion MicroCRM

Ce document formalise les règles et objectifs de l'automatisation CI/CD du projet MicroCRM avant toute mise en œuvre technique. Il définit **quand**, **comment** et **dans quel objectif** les tests et déploiements doivent être exécutés automatiquement.

---

## 1. Plan de testing périodique

### 1.1 Types de tests exécutés

| Couche | Stack | Outil | Description |
|--------|-------|-------|-------------|
| **Back** | Spring Boot, Java 17 | Gradle + JUnit | Tests unitaires et d'intégration (PersonRepository, MicroCRMApplication) |
| **Front** | Angular 17 | Karma + Jasmine | Tests unitaires des composants et services (AppComponent, OrganizationService, PersonService) |

Le script unifié `misc/cicd/run-tests.sh` permet d'exécuter :
- `angular` : tests front uniquement
- `springboot` : tests back uniquement  
- `all` : les deux couches

### 1.2 Fréquence et moments d'exécution

**« Périodique »** signifie ici que les tests sont exécutés à chaque modification du code (déclenchement par événement), et non à intervalles fixes (type cron). Il n'y a pas de run quotidien/hebdomadaire planifié.

| Déclencheur | Fréquence | Objectif |
|-------------|-----------|----------|
| **Push** (toutes branches) | À chaque push | Vérifier que le code ajouté ne casse rien |
| **Pull Request** | À chaque ouverture/mise à jour de PR | Empêcher le merge de code non validé |
| **workflow_dispatch** | Sur demande manuelle | Debug, vérification ponctuelle |

**Résumé** : les tests tournent dès qu'il y a du nouveau code (push ou PR). Aucune exécution planifiée (ex. nightly) n'est prévue pour l'instant.

**Principe** : aucun code ne peut être mergé sans passage des tests. Les tests bloquent la pipeline en cas d'échec.

### 1.3 Branches protégées

Les branches principales (`main`, éventuellement `develop`) sont **protégées** pour renforcer ces règles :

| Règle | Objectif |
|-------|----------|
| **Status checks requis** | Le job CI `test` doit être vert avant tout merge. Impossible de merger une PR dont les tests échouent. |
| **Review obligatoire** | Au moins une approbation (optionnel selon la taille de l'équipe). |
| **Branches à jour** | La branche de la PR doit être à jour avec la cible avant merge (évite les conflits et régressions masquées). |

Ces règles sont configurées dans *Settings → Branches → Branch protection rules* (GitHub). Elles complètent la CI en bloquant le merge côté dépôt, même en cas de contournement du workflow.

### 1.4 Objectifs associés aux tests

| Objectif | Description |
|----------|-------------|
| **Validation fonctionnelle** | Vérifier que les use cases métier (CRUD organizations/persons, liens many-to-many) fonctionnent correctement |
| **Non-régression** | Détecter toute régression introduite par une modification avant qu'elle n'atteigne la branche principale |
| **Qualité** | Maintenir un niveau de couverture minimal et garantir que les tests restent verts sur l'ensemble du code |

**Artéfacts produits** : les résultats JUnit XML (back) sont collectés dans `test-results/` pour intégration avec des outils de rapport (GitHub Actions, SonarQube). Les status checks sont exposés aux règles de protection des branches.

---

## 2. Plan de sécurité

### 2.1 Rôle de l'analyse SonarQube Cloud

- **Analyse statique** du code (back Java, front TypeScript) à chaque push/PR
- **Détection automatique** des vulnérabilités, code smells et bugs
- **Porte de qualité** : blocage du pipeline si le projet ne respecte pas les seuils configurés (ex. : couverture, duplication, dette technique)
- **Historisation** : suivi de l'évolution de la qualité dans le temps

### 2.2 Types de problèmes surveillés

| Catégorie | Exemples |
|-----------|----------|
| **Vulnérabilités** | CVE dans les dépendances (npm, Gradle), injections, exposition de données sensibles |
| **Code smells** | Code dupliqué, complexité cyclomatique élevée, méthodes trop longues |
| **Qualité** | Couverture de tests insuffisante, dette technique excessive, bugs potentiels |
| **Sécurité** | Mots de passe en dur, secrets dans le code, dépendances obsolètes ou vulnérables |

### 2.3 Bonnes pratiques attendues dans la CI

| Pratique | Implémentation |
|----------|----------------|
| **Gestion des secrets** | Utiliser les GitHub Secrets (DOCKERHUB_USERNAME, DOCKERHUB_TOKEN, tokens SonarQube). Jamais de secrets dans le code ou les logs. |
| **Dépendances** | `npm ci` (reproductible) et `./gradlew --no-daemon` (isolation). `npm audit` et `./gradlew dependencyCheck` en option pour détecter les vulnérabilités. |
| **Images de base** | Utiliser des images Alpine ou distroless officielles, maintenues régulièrement. |
| **Privilèges** | Réduire les permissions des workflows au minimum (ex. : `permissions: contents: write` uniquement pour publish). |

---

## 3. Principes de conteneurisation et de déploiement

> **Documentation détaillée** : voir [docs/docker.md](docker.md) pour les choix techniques, les bonnes pratiques de sécurité et le scanning des images.

### 3.1 Rôle des Dockerfiles existants

| Dockerfile | Rôle | Usage |
|------------|------|-------|
| **back/Dockerfile** | Image du backend Spring Boot (JAR sur Eclipse Temurin) | Build indépendant, déploiement back seul |
| **front/Dockerfile** | Image du frontend Angular (Caddy pour servir le SPA) | Build indépendant, déploiement front seul |
| **misc/docker/Dockerfile.nginx** | Image nginx (reverse proxy) | Utilisée par docker-compose pour router trafic |
| **Dockerfile** (racine) | Image monolithique (front + back + supervisor) | Fallback / déploiement tout-en-un |

**Choix** : architecture découplée (back + front séparés) pour faciliter la maintenance, le scaling indépendant et le remplacement de composants. Le Dockerfile racine reste pour les cas legacy ou déploiement simplifié.

### 3.2 Rôle de docker-compose

- **Orchestration locale et dev** : lancer back, front, nginx en une commande
- **Réseau isolé** (`orion-microcrm_network`) pour éviter les conflits avec d'autres apps sur le serveur
- **Overlay dev** : `docker-compose.dev.yml` pour personnaliser les ports
- **Variables d'environnement** : `.env` et `.env.example` pour configurer ports, réseau, etc.

**Usage** : développement local, tests d'intégration en environnement proche de la prod, déploiement sur un serveur unique.

### 3.3 Stratégie de déploiement envisagée

| Phase | Action |
|-------|--------|
| **Build** | À chaque push, build des images Docker (back, front, nginx) sans push |
| **Publication** | Sur push vers `main` : semantic-release pour le versioning, puis build et push des images vers Docker Hub |
| **Tags** | `latest`, SHA du commit, version sémantique (ex. `v1.2.3`) si release |
| **Plateformes** | Multi-arch (`linux/amd64`, `linux/arm64`) pour compatibilité x86 et ARM |

**Déploiement automatisé** : optionnel (webhook vers serveur, Kubernetes, etc.). L’automatisation CI couvre la **construction et la publication** des images ; le déploiement sur l’infra cible peut être déclenché manuellement ou par un outil externe.

---

## 4. Synthèse des approches retenues

| Domaine | Approche | Justification |
|---------|----------|---------------|
| **Tests** | Script unifié (`run-tests.sh`) avec modes angular / springboot / all | Un seul point d’entrée, adaptable à la CI et aux runs manuels |
| **CI** | Tests obligatoires sur push et PR, build conditionnel | Évite de merger du code cassé, limite la charge sur les branches de feature |
| **Sécurité** | Secrets centralisés, analyse SonarQube, images de base maintenues | Réduction des risques sans complexifier excessivement le pipeline |
| **Conteneurs** | Dockerfiles séparés + docker-compose pour l’orchestration | Meilleure modularité et reproductibilité des environnements |
| **Publication** | semantic-release + Docker Hub, uniquement sur `main` | Versioning cohérent et traçabilité des artefacts |

Ces plans précèdent toute mise en œuvre technique et restent réalistes pour un projet de taille modeste (monorepo back + front, déploiement sur un ou quelques serveurs).
