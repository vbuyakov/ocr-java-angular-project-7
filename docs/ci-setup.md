# Configuration du pipeline CI et SonarQube Cloud

Ce document décrit comment configurer le pipeline CI avec GitHub Actions et l'intégration SonarQube Cloud pour le projet Orion MicroCRM.

---

## 1. Variables et secrets à configurer

### 1.1 Secrets (Settings → Secrets and variables → Actions → Secrets)

| Secret | Description | Obligatoire pour |
|--------|-------------|------------------|
| `SONAR_TOKEN` | Token d'authentification SonarCloud (généré depuis sonarcloud.io) | Analyse qualité |

**Note** : `GITHUB_TOKEN` est fourni automatiquement par GitHub Actions. Le workflow `docker-image.yml` utilise ce token pour publier les images vers GitHub Container Registry (ghcr.io) ; aucun secret supplémentaire n'est requis.

### 1.2 Variables (Settings → Secrets and variables → Actions → Variables)

| Variable | Description | Exemple |
|----------|-------------|---------|
| `SONAR_ORGANIZATION` | Clé de l'organisation SonarCloud (visible dans l'URL : sonarcloud.io/organizations/xxx) | `viktor-buiakov` |
| `SONAR_PROJECT_KEY` | Clé du projet SonarCloud (un seul projet pour le monorepo back+front) | `viktor-buiakov_ocr-java-angular-project-7` |

**Comportement** : si `SONAR_ORGANIZATION` est vide, les jobs SonarQube sont ignorés (le pipeline reste utilisable sans SonarCloud).

**Monorepo** : back et front envoient leurs analyses vers le **même projet** SonarCloud, qui agrège les résultats.

---

## 2. Configuration de SonarQube Cloud

### 2.1 Créer un compte et une organisation

1. Rendez-vous sur [sonarcloud.io](https://sonarcloud.io)
2. Connectez-vous avec votre compte GitHub
3. Créez une organisation (ou utilisez celle par défaut)
4. Notez la clé de l'organisation (dans l'URL ou Administration)

### 2.2 Importer le dépôt et créer le projet

1. Dans SonarCloud : **Add new project** (icône +) → **Import from GitHub**
2. Sélectionnez le dépôt (ex. `app` ou le nom de votre repo)
3. SonarCloud propose de créer **un projet** pour le monorepo
4. Lors de la création, choisissez **With GitHub Actions** comme méthode d'analyse
5. Notez la **Project Key** (ex. `viktor-buiakov_ocr-java-angular-project-7`) et configurez-la dans la variable `SONAR_PROJECT_KEY`
6. SonarCloud affiche un **token** : copiez-le et enregistrez-le dans le secret GitHub `SONAR_TOKEN`

**Monorepo** : back et front envoient leurs analyses vers ce même projet. SonarCloud agrège automatiquement les résultats.

### 2.3 Configuration du projet dans SonarCloud

1. Allez dans **Project Settings** → **General Settings**
2. Vérifiez que la **Project Key** correspond à la variable `SONAR_PROJECT_KEY`
3. (Optionnel) Configurez les **Quality Gates** et **Quality Profiles** selon vos exigences
4. (Optionnel) Dans **Administration** → **Analysis Method**, vérifiez que l'analyse est configurée pour GitHub Actions

---

## 3. Intégration dans les Pull Requests

### 3.1 Fonctionnement

1. À chaque **push** et **Pull Request**, le pipeline CI s'exécute
2. Les jobs **sonarqube-back** et **sonarqube-front** envoient les résultats vers le même projet SonarCloud
3. SonarCloud publie un **rapport de qualité** et un **statut de Quality Gate** (pass/fail) comme **check GitHub**
4. Ce check apparaît dans l'onglet **Checks** de la PR et sur le dernier commit

### 3.2 Configurer les branches protégées pour exiger SonarQube

Pour bloquer le merge si la Quality Gate échoue :

1. **GitHub** : *Settings* → *Branches* → *Branch protection rules* → *Add rule*
2. Choisissez la branche à protéger (ex. `main`)
3. Activez **Require status checks to pass before merging**
4. Recherchez et cochez les checks suivants (ils apparaissent après la première analyse) :
   - `SonarQube Backend` (ou le nom affiché par SonarCloud)
   - `SonarQube Frontend`
   - `Test Backend`
   - `Test Frontend`
5. Sauvegardez

Dès lors, une PR ne pourra pas être mergée si l'un de ces checks est en échec.

### 3.3 Vérifier l'intégration

1. Ouvrez une PR ou poussez un commit
2. Attendez la fin du pipeline (GitHub Actions)
3. Dans la PR, onglet **Checks** : vous devez voir les jobs SonarQube et leur statut
4. Un commentaire peut être ajouté par SonarCloud avec un lien vers le rapport détaillé (selon la configuration du projet)

---

## 4. Résumé du pipeline CI

| Job | Déclencheur | Description |
|-----|-------------|-------------|
| Test Backend | push, PR | Exécute `run-tests.sh springboot` |
| Test Frontend | push, PR | Exécute `run-tests.sh angular` |
| Build Backend | après test-back | Gradle `bootJar` |
| Build Frontend | après test-front | npm `build --configuration=production` |
| SonarQube Backend | après build-back | Analyse Gradle + SonarQube plugin |
| SonarQube Frontend | après build-front | SonarQube Scan Action sur `front/` |

**Pipeline CD (images Docker)** : voir [docs/cd-setup.md](cd-setup.md) pour la construction et la publication des images.

---

## 5. Dépannage

| Problème | Solution |
|----------|----------|
| `SONAR_TOKEN` invalid | Régénérez le token dans SonarCloud (My Account → Security → Generate Tokens) |
| Projet non trouvé | Vérifiez `SONAR_PROJECT_KEY` et `SONAR_ORGANIZATION` |
| Jobs SonarQube non exécutés | Vérifiez que `SONAR_ORGANIZATION` est défini (variable non vide) |
| Quality Gate toujours rouge | Ajustez les seuils dans SonarCloud ou corrigez le code pour respecter les règles |
