# Dette technique – Orion MicroCRM

Ce document analyse la dette technique du projet en croisant les résultats SonarQube, les métriques DORA et les KPIs opérationnels. Il identifie les points critiques et propose des préconisations réalistes et priorisées.

---

## 1. Sources d'analyse

| Source | Données |
|--------|---------|
| **SonarCloud** | Analyse statique back (Java 17 / Spring Boot 3) et front (TypeScript / Angular 17) via `ci.yml` |
| **Métriques DORA** | Change Failure Rate 25%, Lead Time 2–4 jours, MTTR ELK ~3 jours (voir [kpi-dora-analysis.md](kpi-dora-analysis.md)) |
| **KPIs opérationnels** | Couverture tests, durée pipeline, taux d'erreurs |
| **CHANGELOG + commits** | Analyse des patterns de bug fixes et itérations de correction |

---

## 2. Résultats SonarQube

### 2.1 Backend – Spring Boot 3 / Java 17

L'analyse SonarCloud est déclenchée par le job `sonarqube-back` du workflow `ci.yml` à chaque push et PR.

**Points observés :**

| Catégorie | Constat | Sévérité |
|-----------|---------|----------|
| **Couverture** | Tests JUnit couvrant `PersonRepository` et `MicroCRMApplication`. Les contrôleurs REST et services métier peuvent avoir une couverture insuffisante si seule la couche repository est testée. | Moyenne |
| **Code smells** | Relations many-to-many (Organizations ↔ Persons) impliquent des risques de cycles de chargement JPA (`FetchType.EAGER` implicite ou boucles de sérialisation JSON). | Moyenne |
| **Sécurité** | Absence visible de configuration de sécurité HTTP (Spring Security) : endpoints API potentiellement non protégés en production. | Haute |
| **Bugs potentiels** | H2 en mémoire utilisé comme base par défaut (profil Spring Boot sans `spring.datasource` explicite) : les données sont perdues à chaque redémarrage du container. | **Critique** |
| **Dépendances** | Gradle + Spring Boot 3 avec Java 17 : vérifier les dépendances transitives signalées par SonarQube ou un `./gradlew dependencyCheckAnalyze`. | Basse |

### 2.2 Frontend – Angular 17 / TypeScript

L'analyse est déclenchée par le job `sonarqube-front` via l'action `SonarSource/sonarqube-scan-action`.

**Points observés :**

| Catégorie | Constat | Sévérité |
|-----------|---------|----------|
| **Couverture** | Tests Jasmine sur `AppComponent`, `OrganizationService`, `PersonService`. Absence probable de tests sur les composants de formulaire et de liste. | Moyenne |
| **Code smells** | Services `OrganizationService` et `PersonService` suivent probablement un pattern CRUD identique — risque de duplication de logique (même structure `HttpClient.get/post/put/delete`). | Basse |
| **Gestion des erreurs** | Appels `HttpClient` sans gestion systématique des erreurs (`catchError`) : une erreur réseau peut laisser l'UI dans un état indéterminé sans message utilisateur. | Moyenne |
| **Sécurité** | Pas d'authentification côté front (pas de guards Angular, pas de JWT observable) : toutes les routes sont accessibles sans connexion. | Haute |
| **Accessibilité** | Formulaires CRUD sans labels ARIA ni gestion du focus : non conforme WCAG 2.1 A. | Basse |

---

## 3. Point critique identifié : persistance des données en production

### 3.1 Problème

Spring Boot configure **H2 en mémoire** par défaut lorsqu'aucune source de données n'est explicitement définie. Or, dans l'architecture actuelle :

- L'application tourne dans un container Docker
- Chaque `docker compose up` ou redémarrage du container **efface toutes les données** (organizations, persons, relations)
- Le workflow CD (`docker-image.yml`) déclenche automatiquement `./misc/cicd/prod-up.sh --app-only` à chaque release, ce qui implique un redémarrage régulier des containers

**Impact** : en production (ocr-ja7.buyakov.com), toute donnée créée par les utilisateurs est perdue à chaque déploiement automatique — soit plusieurs fois par semaine selon le CHANGELOG.

### 3.2 Conséquences mesurées

| Conséquence | Lien DORA/KPI |
|-------------|--------------|
| Données perdues à chaque déploiement | Impacte la confiance utilisateur (KPI disponibilité réelle) |
| Impossibilité de tester des scénarios persistants en prod | Masque les bugs de régression liés aux données existantes |
| Absence de sauvegarde possible (données volatiles) | Rend le plan de sauvegarde partiellement inopérant |
| CFR sous-estimé : les déploiements réussissent techniquement mais causent une perte de données silencieuse | CFR réel probablement supérieur à 25% |

### 3.3 Correction préconisée

**Option 1 – Court terme (profil `prod` avec H2 fichier)** :

```properties
# back/src/main/resources/application-prod.properties
spring.datasource.url=jdbc:h2:file:/data/microcrm;AUTO_SERVER=TRUE
spring.datasource.driver-class-name=org.h2.Driver
spring.jpa.hibernate.ddl-auto=update
```

Monter un volume Docker pour `/data` :

```yaml
# docker-compose.prod.yml
services:
  back:
    volumes:
      - microcrm-data:/data
volumes:
  microcrm-data:
```

**Option 2 – Long terme (PostgreSQL)** :

Migrer vers PostgreSQL avec un container dédié ou un service managé. Nécessite l'ajout de la dépendance `spring-boot-starter-data-jpa` + driver PostgreSQL et une migration Flyway/Liquibase.

**Effort** : Option 1 = 2–3 heures. Option 2 = 1–2 jours.

---

## 4. Analyse croisée : dette technique × métriques DORA

### 4.1 Change Failure Rate (CFR) et dette

Le CFR de 25% (1 hotfix sur 4 releases) est directement lié à deux causes de dette :

| Cause de dette | Release impactée | Correction |
|----------------|-----------------|------------|
| Pipeline CI/CD mal configuré (ci files for deploy) | v1.0.1 | Corriger les scripts de déploiement en intégrant des tests smoke post-déploiement |
| Intégration ELK insuffisamment testée avant merge | v1.1.0 (5 bug fixes) | Ajouter un environnement de staging ELK pour valider la configuration avant la prod |

**Réduction attendue du CFR** : en introduisant des smoke tests post-déploiement (`curl` health-check sur `/actuator/health`), le CFR devrait descendre sous 10% (niveau `High` DORA).

### 4.2 Lead Time et dette de tests

Le Lead Time de 3–4 jours pour l'intégration ELK (v1.1.0 : 5 corrections itératives) révèle un **déficit de tests d'intégration** pour les composants d'infrastructure. Chaque correction a nécessité un cycle complet push → CI → Release → Docker → Deploy (~12 min) pour être validée.

**Dette associée** : absence de tests d'intégration Docker Compose (type `docker-compose.test.yml`) permettant de valider localement la configuration ELK avant le push.

### 4.3 MTTR et dette de monitoring

Le MTTR de ~3 jours pour les incidents ELK (vs < 4 heures pour l'app) reflète :
- Absence d'alerting automatique sur l'état de la stack ELK
- Diagnostic manuel (logs Filebeat, curl Elasticsearch) sans tableau de bord opérationnel
- Pas de runbook documenté pour les incidents ELK courants

**Dette associée** : absence de health-checks automatisés et d'alerting.

---

## 5. Tableau de bord de la dette technique

| # | Item de dette | Catégorie | Impact | Effort | Priorité |
|---|--------------|-----------|--------|--------|---------|
| 1 | **Base de données H2 en mémoire en prod** (perte de données) | Architecture | Critique | Faible (H2 fichier) / Moyen (PostgreSQL) | **P0** |
| 2 | **Absence de sécurité API** (endpoints non protégés) | Sécurité | Haute | Moyen (Spring Security basic) | **P1** |
| 3 | **Absence de smoke tests post-déploiement** | CI/CD | Haute | Faible | **P1** |
| 4 | **Absence d'alerting ELK** (pas de Watcher Kibana) | Monitoring | Moyenne | Faible | **P2** |
| 5 | **Gestion des erreurs HTTP côté Angular** (pas de catchError) | Front | Moyenne | Faible | **P2** |
| 6 | **Couverture tests insuffisante** (contrôleurs REST non testés) | Qualité | Moyenne | Moyen | **P2** |
| 7 | **Duplication services Angular** (CRUD pattern identique) | Maintenabilité | Basse | Faible | **P3** |
| 8 | **Pas de tests E2E** (flux CRUD non couverts) | Qualité | Moyenne | Élevé | **P3** |

---

## 6. Préconisations par priorité

### P0 – Critique (à traiter immédiatement)

**Migrer la base de données vers H2 fichier ou PostgreSQL**

1. Créer `back/src/main/resources/application-prod.properties` avec `jdbc:h2:file:/data/microcrm`
2. Ajouter le volume `microcrm-data` dans `docker-compose.prod.yml`
3. Ajouter le plan de sauvegarde documenté (voir [prod-deploy.md](prod-deploy.md))
4. Tester le redémarrage : vérifier la persistance des données après `docker compose restart back`

---

### P1 – Haute priorité (sprint suivant)

**Smoke tests post-déploiement**

Ajouter un step au job `deploy` du workflow `docker-image.yml` :

```yaml
- name: Smoke test
  uses: appleboy/ssh-action@v1
  with:
    host: ${{ secrets.PROD_HOST }}
    username: ${{ secrets.PROD_SSH_USER }}
    key: ${{ secrets.PROD_SSH_KEY }}
    script: |
      sleep 15
      curl -f http://localhost:8080/actuator/health || exit 1
      echo "Smoke test passed"
```

**Sécurité API**

Ajouter Spring Security avec au minimum une authentification Basic pour les endpoints d'administration, ou configurer CORS correctement pour restreindre les origines autorisées.

---

### P2 – Priorité normale (backlog à planifier)

**Alerting Kibana**

Configurer un Watcher Elasticsearch déclenchant une notification (email ou webhook) si le taux d'erreurs 5xx dépasse 2% sur 5 minutes. Documentation : [Kibana Alerting](https://www.elastic.co/guide/en/kibana/current/alerting-getting-started.html).

**Gestion des erreurs Angular**

Centraliser la gestion des erreurs HTTP avec un `HttpInterceptor` qui catch les erreurs réseau et affiche un toast/snackbar à l'utilisateur.

**Couverture des tests back**

Ajouter des tests JUnit pour les contrôleurs REST (`@WebMvcTest`) avec mock des services, cibler ≥ 70% de couverture globale.

---

### P3 – Basse priorité (dette accumulable à court terme)

**Abstraction des services Angular**

Créer un service générique `CrudService<T>` dont héritent `OrganizationService` et `PersonService` pour éliminer la duplication du pattern CRUD (endpoints, méthodes get/post/put/delete).

**Tests E2E**

Intégrer Playwright ou Cypress pour couvrir les scénarios utilisateur principaux (créer une organization, ajouter une person, vérifier le lien many-to-many).

---

## 7. Suivi de la résorption

Mesurer la dette à intervalles réguliers :

| Indicateur | Cible 1 mois | Cible 3 mois |
|-----------|-------------|-------------|
| H2 fichier ou PostgreSQL en prod | ✓ | ✓ PostgreSQL |
| CFR (DORA) | < 15% | < 10% |
| Couverture tests (SonarQube) | > 60% | > 75% |
| Smoke tests post-déploiement | ✓ | ✓ |
| Alerting ELK actif | — | ✓ |

Ces indicateurs sont mesurables via SonarCloud (couverture), le CHANGELOG (CFR), et les workflows GitHub Actions (smoke tests). Ils doivent être revus lors de chaque retrospective ou sprint review.
