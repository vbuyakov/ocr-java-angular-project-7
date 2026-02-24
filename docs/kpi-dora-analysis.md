# Métriques DORA et KPIs – Orion MicroCRM

Ce document présente les métriques DORA calculées à partir du CHANGELOG et des workflows GitHub Actions, les KPIs opérationnels de MicroCRM, ainsi que les dashboards Kibana associés.

---

## 1. Métriques DORA

Les métriques DORA (DevOps Research and Assessment) mesurent la performance d'une équipe de livraison logicielle selon quatre axes : fréquence de déploiement, délai de mise en production, taux d'échec des changements et délai de rétablissement.

### 1.1 Sources de données

| Source | Données extraites |
|--------|-------------------|
| **CHANGELOG.md** | Dates des releases (v1.0.0 à v1.2.0), nature des changements (features/bug fixes) |
| **GitHub Actions – `docker-image.yml`** | Déclenchements du job `deploy` (push `main`, `workflow_run` après Release) |
| **GitHub Actions – `ci.yml`** | Durées de build et taux d'échec des pipelines |
| **GitHub Actions – `release.yml`** | Timestamps des releases automatisées via semantic-release |

### 1.2 Deployment Frequency (Fréquence de déploiement)

**Définition** : nombre de déploiements en production par unité de temps.

**Calcul sur la période observée (2026-02-16 → 2026-02-23, soit 8 jours) :**

| Release | Date | Type |
|---------|------|------|
| v1.0.0 | 2026-02-16 | Initial release (CI, Docker, SonarQube) |
| v1.0.1 | 2026-02-16 | Hotfix (ci files for deploy) |
| v1.1.0 | 2026-02-20 | Feature (ELK stack, nginx config) |
| v1.2.0 | 2026-02-23 | Feature (production deploy improvements) |

> En complément des 4 releases officielles, les commits `deploy on server` et `deploy on server on test branch` (v1.2.0) indiquent 2 à 3 déploiements de validation supplémentaires sur la branche `test`.

**Résultat** : ~4 déploiements prod officiels sur 8 jours = **0,5 déploiement/jour**.

**Niveau DORA** : `High` (une fois par jour à une fois par semaine). La cadence est soutenue pour un projet en phase de bootstrap ; avec une équipe plus grande, l'objectif `Elite` (plusieurs fois par jour) nécessiterait des déploiements par feature flag ou canary.

**Piste d'amélioration** : mettre en place des déploiements automatiques sur une branche `staging` pour chaque PR mergée, permettant de découpler la validation fonctionnelle du rythme de release.

---

### 1.3 Lead Time for Changes (Délai de mise en production)

**Définition** : temps écoulé entre le premier commit d'une fonctionnalité et son déploiement en production.

**Pipeline automatisé actuel :**

```
Push (main) → CI (~5 min) → Release (~2 min) → Docker Image (~4 min) → Deploy SSH (~1 min)
                                                                         ↑
                                                              Total pipeline : ~12 min
```

**Délai observé par release :**

| Release | Délai développement → prod | Notes |
|---------|-----------------------------|-------|
| v1.0.1 | < 2 heures | Hotfix déployé le même jour que v1.0.0 |
| v1.1.0 | ~4 jours | Intégration ELK avec plusieurs itérations de correction |
| v1.2.0 | ~3 jours | Ajustements déploiement prod |

**Résultat** : délai moyen de **2 à 4 jours** pour les features complètes ; **< 4 heures** pour les hotfixes via le pipeline automatisé.

**Niveau DORA** : `Medium` pour les features (une semaine à un mois). Les hotfixes atteignent le niveau `High`. La durée reflète principalement le temps de développement, pas le pipeline (12 min).

**Piste d'amélioration** : découper les fonctionnalités en commits plus atomiques et adopter une stratégie trunk-based development pour raccourcir les branches de longue durée.

---

### 1.4 Change Failure Rate (Taux d'échec des changements)

**Définition** : pourcentage de déploiements nécessitant un rollback, hotfix ou patch d'urgence.

**Analyse du CHANGELOG :**

| Release | Bug fixes immédiats | Évaluation |
|---------|---------------------|------------|
| v1.0.0 → v1.0.1 | 1 fix critique (`ci files for deploy`) | Déploiement CD cassé → hotfix le même jour |
| v1.1.0 | 5 fixes successifs (ELK : logs, sécurité, Logstash) | Intégration ELK instable, corrections itératives avant stabilisation |
| v1.2.0 | 0 fix | Release stable |

> Le ratio releases problématiques / total : **2 sur 4** (v1.0.0 et v1.1.0). Cependant, les 5 bugs de v1.1.0 sont des corrections d'une fonctionnalité nouvelle (ELK) et non des régressions de prod — à pondérer différemment d'un hotfix critique.

**CFR conservatrice** : 1 hotfix critique (v1.0.1) = **25%** (1/4 releases).

**Niveau DORA** : `Medium` (15–45%). Le seul rollback/hotfix véritable est v1.0.1 ; les bugs de v1.1.0 sont des corrections de développement itératif.

**Piste d'amélioration** : renforcer les tests d'intégration pour le pipeline CI/CD lui-même (smoke tests post-déploiement, validation de la connexion SSH et du `prod-up.sh` en environnement de staging avant la prod).

---

### 1.5 Mean Time To Recover (Délai moyen de rétablissement)

**Définition** : temps moyen pour restaurer le service après une défaillance en production.

**Incidents observés :**

| Incident | Date détection | Date résolution | MTTR |
|----------|---------------|-----------------|------|
| Pipeline CI/CD cassé (v1.0.1) | 2026-02-16 | 2026-02-16 | < 4 heures |
| ELK non fonctionnel (5 fixes en v1.1.0) | ~2026-02-17 | 2026-02-20 | ~3 jours |

> L'incident ELK a un MTTR élevé (~3 jours) mais il s'agit d'un monitoring, non de l'application elle-même. L'application restait accessible pendant cette période.

**MTTR applicatif** : < 4 heures (niveau `Elite`).
**MTTR monitoring** : ~3 jours (niveau `Low`) — à améliorer.

**Piste d'amélioration** : créer un health-check automatique de la stack ELK déclenché après chaque déploiement `--elk-only`, avec alerte si Kibana ne répond pas sous 5 minutes.

---

### 1.6 Synthèse DORA

| Métrique | Valeur mesurée | Niveau DORA | Objectif |
|----------|---------------|-------------|----------|
| Deployment Frequency | ~0,5/jour | **High** | Elite : plusieurs/jour |
| Lead Time for Changes | 2–4 jours (features) / < 4h (hotfixes) | **Medium/High** | High : < 1 jour |
| Change Failure Rate | 25% | **Medium** | High : < 15% |
| MTTR (app) | < 4 heures | **High/Elite** | Elite : < 1 heure |

---

## 2. KPIs opérationnels MicroCRM

Cinq KPIs complémentaires aux métriques DORA, adaptés à la taille et aux enjeux de MicroCRM.

### KPI 1 – Disponibilité de l'application (Uptime)

**Objectif** : ≥ 99% sur 30 jours glissants.

**Calcul** : `(temps total - temps d'indisponibilité) / temps total × 100`

**Source ELK** : logs Nginx (`orion-microcrm-nginx`) dans l'index `ocr-ja7-logs-*`. Absence de réponse HTTP ou erreurs 502/503 consécutives signalent une indisponibilité.

**Kibana** : dashboard "Santé app" → courbe de disponibilité par tranche de 5 minutes.

**Analyse** : lors des redémarrages applicatifs (`./misc/cicd/prod-up.sh --app-only`), une fenêtre de 30 à 60 secondes d'indisponibilité est observée (rechargement des containers). Sans mécanisme de zero-downtime, chaque déploiement impacte la disponibilité.

**Amélioration** : configurer un health-check Docker (`HEALTHCHECK`) et utiliser `--no-trunc` + rolling restart pour réduire le downtime à zéro lors des mises à jour.

---

### KPI 2 – Taux d'erreurs HTTP (4xx/5xx)

**Objectif** : taux d'erreurs 5xx < 1% du trafic total ; 4xx < 5%.

**Calcul** : `count(status >= 500) / count(all requests) × 100`

**Source ELK** : champ `http.response.status_code` dans les logs Nginx (Filebeat → Elasticsearch, index `ocr-ja7-logs-*`).

**Anomalies détectables** :
- Pic de 502/504 pendant les redémarrages Docker
- Augmentation des 404 après un déploiement (routes Angular modifiées sans mise à jour Nginx)
- Erreurs 500 sur `/api/organizations` ou `/api/persons` (régression backend)

**Amélioration** : ajouter un alerting Kibana Watcher déclenchant une notification si le taux 5xx dépasse 2% sur une fenêtre de 5 minutes.

---

### KPI 3 – Temps de réponse moyen des API backend

**Objectif** : P95 < 500 ms sur les endpoints CRUD (`/api/organizations`, `/api/persons`).

**Source ELK** : champ `http.response.time` ou `upstream_response_time` dans les logs Nginx / logs Spring Boot (format JSON logback).

**Analyse actuelle** : Spring Boot avec H2 en mémoire (profil dev par défaut). Les temps de réponse sont naturellement faibles sur une base en mémoire, mais une bascule vers une base persistante (PostgreSQL) en prod modifierait significativement ce KPI.

**Anomalie à surveiller** : latences anormalement élevées après un déploiement (JVM warmup Spring Boot : les 10 premières requêtes post-redémarrage peuvent être lentes en raison du chargement des classes).

**Amélioration** : activer les logs de durée de réponse dans Spring Boot (`logging.level.org.springframework.web=DEBUG`) et les envoyer vers ELK via le volume partagé.

---

### KPI 4 – Couverture des tests (SonarQube)

**Objectif** : couverture globale ≥ 70% (back Java + front TypeScript).

**Source** : SonarCloud (workflow `ci.yml`, jobs `sonarqube-back` et `sonarqube-front`), accessible sur https://sonarcloud.io.

**Analyse** :
- **Back** : tests JUnit couvrant `PersonRepository` et `MicroCRMApplication`. La couverture des services métier et des contrôleurs REST est un point à surveiller.
- **Front** : tests Jasmine/Karma sur `AppComponent`, `OrganizationService`, `PersonService`. La couverture des composants de liste/formulaire peut être insuffisante.

**Anomalie identifiée** : absence de tests d'intégration end-to-end (E2E, type Cypress/Playwright) — les interactions Angular ↔ Spring Boot ne sont pas couvertes.

**Amélioration** : cibler en priorité les services critiques (PersonService, OrganizationService côté back) pour porter la couverture au-dessus du seuil SonarQube.

---

### KPI 5 – Durée du pipeline CI (Time to feedback)

**Objectif** : pipeline complet (CI + Release + Docker + Deploy) ≤ 15 minutes.

**Source** : GitHub Actions – onglet "Actions", durées des workflows `ci.yml`, `release.yml`, `docker-image.yml`.

**Estimation actuelle** :

| Étape | Durée estimée |
|-------|--------------|
| Tests back (Gradle + JUnit) | ~3 min |
| Tests front (Karma + Jasmine) | ~2 min |
| Build back + front | ~3 min |
| SonarQube (back + front en parallèle) | ~3 min |
| Release (semantic-release) | ~1 min |
| Build + push images Docker (GHCR) | ~4 min |
| Deploy SSH | ~1 min |
| **Total end-to-end** | **~12–17 min** |

**Anomalie** : les jobs SonarQube (`sonarqube-back`, `sonarqube-front`) s'exécutent après les tests ET le build, ajoutant une dépendance séquentielle qui allonge le pipeline. Ils pourraient s'exécuter en parallèle du build si la contrainte `needs: [test-back, build-back]` est allégée.

**Amélioration** : paralléliser les analyses SonarQube avec le build Docker pour descendre sous les 12 minutes.

---

## 3. Identification d'anomalies via ELK / Kibana

### 3.1 Anomalies détectables dans les logs

| Anomalie | Symptôme dans Kibana | Cause probable | Action |
|----------|---------------------|----------------|--------|
| **Downtime lors des déploiements** | Absence de logs Nginx pendant 30–60 s + spike 502 | Rechargement Docker sans zero-downtime | Rolling restart ou health-check |
| **Gaps dans l'indexation Filebeat** | Absence de documents dans `ocr-ja7-logs-*` sur une plage | Filebeat déconnecté ou volume `nginx-logs` absent | Vérifier `docker logs ocr-ja7-filebeat` |
| **Erreurs Logstash / parsing** | Messages `_grokparsefailure` dans Kibana | Format de log non conforme au pipeline Logstash | Ajuster `misc/elk/logstash.conf` |
| **Latences Spring Boot au démarrage** | Pics de latence sur les 5 premières minutes post-déploiement | JVM warmup (chargement des classes, initialisation du contexte Spring) | Ajouter un warmup endpoint (`/actuator/health`) dans le script de déploiement |
| **Accumulation d'index Elasticsearch** | Index `ocr-ja7-logs-YYYY.MM.dd` trop nombreux | Pas d'ILM configuré | Configurer Index Lifecycle Management ou purge manuelle mensuelle |

### 3.2 Requêtes Kibana utiles (KQL)

```kql
# Toutes les erreurs 5xx des 24 dernières heures
http.response.status_code >= 500

# Requêtes lentes (> 1s) sur l'API backend
upstream_response_time > 1 AND url.path : "/api/*"

# Logs Spring Boot uniquement
container.name : "orion-microcrm-back-1"

# Événements lors d'un déploiement (recherche manuelle)
@timestamp >= "2026-02-23T10:00:00" AND @timestamp <= "2026-02-23T10:30:00"
```

---

## 4. Dashboards Kibana décrits

### Dashboard 1 – Santé de l'application

**Objectif** : vue temps réel de l'état opérationnel de MicroCRM.

| Visualisation | Type | Métrique |
|---------------|------|---------|
| Uptime (%) | Gauge | `(1 - count(502,503)/count(*)) × 100` sur 30 jours |
| Taux d'erreurs HTTP | Pie chart | Répartition 2xx / 3xx / 4xx / 5xx |
| Volume de requêtes | Bar chart (time) | Requêtes/minute sur 24h |
| Latence P50/P95 | Line chart | `upstream_response_time` percentiles |
| Top 10 URLs par erreurs | Data table | `url.path` filtré sur 4xx/5xx |

**Index** : `ocr-ja7-logs-*` / **Refresh** : 1 minute

---

### Dashboard 2 – CI/CD & Déploiements

**Objectif** : suivi des déploiements et corrélation avec les anomalies de production.

| Visualisation | Type | Source |
|---------------|------|--------|
| Fréquence de déploiement | Bar chart hebdomadaire | CHANGELOG + GitHub Actions logs |
| Durée moyenne du pipeline | Metric | Workflow durations (GitHub API) |
| Incidents post-déploiement | Annotation sur courbe de trafic | Corrélation timestamp déploiement + spike erreurs |
| CFR (taux d'échec) | Metric | Releases avec hotfix / total releases |

**Note** : ce dashboard nécessite l'ingestion des logs GitHub Actions dans Elasticsearch (via Logstash webhook ou GitHub Actions → Filebeat) pour être pleinement automatisé. En attendant, les données peuvent être saisies manuellement depuis le CHANGELOG.

---

### Dashboard 3 – Métriques DORA (synthèse)

**Objectif** : tableau de bord exécutif pour suivre la performance DevOps dans le temps.

| Métrique | Visualisation | Cible |
|----------|--------------|-------|
| Deployment Frequency | Gauge + trend mensuel | ≥ 1/jour |
| Lead Time for Changes | Gauge + histogramme | < 1 jour |
| Change Failure Rate | Gauge (rouge/orange/vert) | < 15% |
| MTTR | Gauge + boxplot | < 1 heure |

**Mise à jour** : manuelle à chaque release (basée sur le CHANGELOG) jusqu'à l'automatisation via l'API GitHub.

---

## 5. Synthèse et priorités d'amélioration

| Priorité | Action | Impact DORA / KPI |
|----------|--------|-------------------|
| 1 | Smoke tests post-déploiement (health-check automatique) | ↓ CFR, ↓ MTTR |
| 2 | Zero-downtime deploy (rolling restart Docker) | ↑ Uptime KPI |
| 3 | Health-check ELK après `--elk-only` | ↓ MTTR monitoring |
| 4 | Alerting Kibana Watcher sur taux 5xx | ↓ MTTR |
| 5 | Tests E2E (Cypress) sur les flux CRUD critiques | ↓ CFR |
