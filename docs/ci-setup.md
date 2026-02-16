# Configuration du pipeline CI et SonarQube Cloud

Ce document décrit comment configurer le pipeline CI avec GitHub Actions et l'intégration SonarQube Cloud pour le projet Orion MicroCRM.

---

## 1. Variables et secrets à configurer

### 1.1 Secrets (Settings → Secrets and variables → Actions → Secrets)

| Secret | Description | Obligatoire pour |
|--------|-------------|------------------|
| `SONAR_TOKEN` | Token d'authentification SonarCloud (généré depuis sonarcloud.io) | Analyse qualité |
| `DOCKERHUB_USERNAME` | Nom d'utilisateur Docker Hub | Publication des images |
| `DOCKERHUB_TOKEN` | Token d'accès Docker Hub (Access Token, pas le mot de passe) | Publication des images |

**Note** : `GITHUB_TOKEN` est fourni automatiquement par GitHub Actions, inutile de le créer.

### 1.2 Variables (Settings → Secrets and variables → Actions → Variables)

| Variable | Description | Exemple |
|----------|-------------|---------|
| `SONAR_ORGANIZATION` | Clé de l'organisation SonarCloud (visible dans l'URL : sonarcloud.io/organizations/xxx) | `my-org` |
| `SONAR_PROJECT_KEY_BACK` | Clé du projet backend dans SonarCloud | `orion-microcrm-back` |
| `SONAR_PROJECT_KEY_FRONT` | Clé du projet frontend dans SonarCloud | `orion-microcrm-front` |

**Comportement** : si `SONAR_ORGANIZATION` est vide, les jobs SonarQube sont ignorés (le pipeline reste utilisable sans SonarCloud).

---

## 2. Configuration de SonarQube Cloud

### 2.1 Créer un compte et une organisation

1. Rendez-vous sur [sonarcloud.io](https://sonarcloud.io)
2. Connectez-vous avec votre compte GitHub
3. Créez une organisation (ou utilisez celle par défaut)
4. Notez la clé de l'organisation (dans l'URL ou Administration)

### 2.2 Importer le dépôt et créer les projets

1. Dans SonarCloud : **Add new project** → **Import from GitHub**
2. Sélectionnez le dépôt `orion-microcrm` (ou le nom de votre repo)
3. SonarCloud propose de créer un projet. Pour un **monorepo** (back + front), créez **deux projets** :
   - **Projet Backend** : clé `orion-microcrm-back` (ou `votre-org_orion-microcrm-back`)
   - **Projet Frontend** : clé `orion-microcrm-front` (ou `votre-org_orion-microcrm-front`)
4. Lors de la création, choisissez **With GitHub Actions** comme méthode d'analyse
5. Pour chaque projet, SonarCloud affiche un **token** : copiez-le et enregistrez-le dans le secret GitHub `SONAR_TOKEN`

**Important** : un seul token SonarCloud peut couvrir plusieurs projets de la même organisation. Utilisez le token fourni lors de la configuration du premier projet.

### 2.3 Configuration des projets dans SonarCloud

Pour chaque projet (backend, frontend) :

1. Allez dans **Project Settings** → **General Settings**
2. Vérifiez que la **Project Key** correspond aux variables `SONAR_PROJECT_KEY_BACK` et `SONAR_PROJECT_KEY_FRONT`
3. (Optionnel) Configurez les **Quality Gates** et **Quality Profiles** selon vos exigences
4. (Optionnel) Dans **Administration** → **Analysis Method**, vérifiez que l'analyse est configurée pour GitHub Actions

---

## 3. Intégration dans les Pull Requests

### 3.1 Fonctionnement

1. À chaque **push** et **Pull Request**, le pipeline CI s'exécute
2. Les jobs **sonarqube-back** et **sonarqube-front** envoient les résultats à SonarCloud
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
| Build Docker | après builds | Build des images (sans push) |
| Publish | push sur `main` | Push des images vers Docker Hub |

---

## 5. Dépannage

| Problème | Solution |
|----------|----------|
| `SONAR_TOKEN` invalid | Régénérez le token dans SonarCloud (My Account → Security → Generate Tokens) |
| Projet non trouvé | Vérifiez `SONAR_PROJECT_KEY_*` et `SONAR_ORGANIZATION` |
| Jobs SonarQube non exécutés | Vérifiez que `SONAR_ORGANIZATION` est défini (variable non vide) |
| Quality Gate toujours rouge | Ajustez les seuils dans SonarCloud ou corrigez le code pour respecter les règles |
