# Mission Étape 3 — Déploiements basiques avec RollingUpdate

## Objectif

Packager une application en Deployment et Service, puis appliquer une stratégie RollingUpdate sans coupure de service.

---

## A. À lire

**Ouvrages et documentation :**
- *Kubernetes in Action* — chapitre sur les Deployments
- Documentation Kubernetes : *Updating a Deployment* et *Rolling Update Strategy*
- CKAD : modules *Deployments* et *Rolling Updates and Rollbacks*

**Questions à explorer pendant la lecture :**
- Quelle est la différence entre un ReplicaSet et un Deployment ?
- Comment Kubernetes garantit-il la disponibilité pendant un rolling update ?
- Que se passe-t-il si un pod du nouveau ReplicaSet ne devient pas prêt ?
- Comment revenir en arrière si une mise à jour échoue ?

---

## B. À créer

### 1. Manifest de l'application — `infra/apps/demo/deployment.yaml`

**Exigences :**
- Déploiement d'une application web simple (image publique, ex. nginx ou équivalent)
- 3 réplicas, avec labels et sélecteurs cohérents
- Stratégie RollingUpdate avec `maxUnavailable` et `maxSurge` explicitement définis
- Conteneur exposant un port HTTP

**Critères d'acceptation :**
- Le manifest est appliqué dans le namespace `dev`
- Les 3 pods sont créés et passent en état `Running`
- La stratégie de mise à jour est visible dans la configuration du Deployment

### 2. Manifest du Service — `infra/apps/demo/service.yaml`

**Exigences :**
- Service de type ClusterIP
- Sélecteur aligné avec les labels du Deployment
- Port cible correspondant au port exposé par le conteneur

**Critères d'acceptation :**
- Le Service est créé dans le namespace `dev`
- Les endpoints du Service pointent vers les 3 pods du Deployment

### 3. Script de validation — `tests/step_03_validation.sh`

**Exigences :**
- Script bash exécutable
- Vérifie la présence des ressources (Deployment, Service) dans le namespace `dev`
- Vérifie que le Deployment est disponible (3 réplicas prêts)
- Vérifie que les endpoints du Service sont peuplés
- Vérifie la stratégie de mise à jour configurée
- Écrit le résultat dans `tests/step_03_result.txt` avec le marqueur `PASS` en cas de succès

**Critères d'acceptation :**
- Le script s'exécute sans erreur
- Le fichier de résultat contient `PASS` et le détail des vérifications

### 4. ADR — `infra/adrs/adr_step_03_final.md`

**Exigences :**
- Contexte : pourquoi cette application est déployée de cette façon
- Décision : choix de la stratégie RollingUpdate (paramètres `maxUnavailable` et `maxSurge`)
- Conséquences : impact sur la disponibilité, le temps de déploiement, la consommation de ressources
- Alternatives envisagées et raisons du rejet

**Critères d'acceptation :**
- L'ADR suit le format standard (Contexte, Décision, Conséquences)
- Les paramètres choisis sont justifiés par rapport au besoin de disponibilité

---

## C. À livrer

### Preuves attendues

1. **Fichiers créés :**
   - `infra/apps/demo/deployment.yaml`
   - `infra/apps/demo/service.yaml`
   - `tests/step_03_validation.sh`
   - `tests/step_03_result.txt`
   - `infra/adrs/adr_step_03_final.md`

2. **Validation :**
   - Exécuter `tests/step_03_validation.sh`
   - Le fichier `tests/step_03_result.txt` doit contenir `PASS`

3. **Démonstration manuelle (à documenter dans le résultat) :**
   - Lancer une mise à jour de l'image du Deployment
   - Observer le comportement du rolling update (nouveaux pods créés, anciens supprimés progressivement)
   - Vérifier que le Service reste disponible pendant la mise à jour

### Commandes de validation suggérées

- `kubectl get deployments -n dev` — vérifier l'état du Deployment
- `kubectl get replicasets -n dev` — observer les ReplicaSets (ancien et nouveau)
- `kubectl get pods -n dev` — vérifier les pods
- `kubectl get endpoints -n dev` — vérifier les endpoints du Service
- `kubectl rollout status deployment/<nom> -n dev` — suivre le déploiement
- `kubectl rollout history deployment/<nom> -n dev` — voir l'historique des révisions

### Marqueurs de réussite

- [ ] Les 3 réplicas sont disponibles et prêts
- [ ] Le Service expose correctement l'application
- [ ] Une mise à jour d'image se fait sans interruption de service
- [ ] Le script de validation retourne `PASS`
- [ ] L'ADR documente les choix et leurs justifications

---

## Risque métier

Une mauvaise configuration de la stratégie RollingUpdate (ex. `maxUnavailable` trop élevé) peut entraîner une indisponibilité temporaire de l'application lors d'un déploiement. En production, cela se traduit par des utilisateurs impactés et une perte de confiance. Il est donc essentiel de comprendre l'impact de chaque paramètre avant de les appliquer à des environnements critiques.

---

## Estimation de temps

| Activité | Durée estimée |
|----------|---------------|
| Lecture et exploration des concepts | 2h |
| Création des manifests (Deployment, Service) | 1h30 |
| Test manuel du rolling update | 1h30 |
| Rédaction du script de validation | 1h |
| Rédaction de l'ADR | 1h |
| **Total** | **7h** |

---

## Rappel

Cette mission est une étape vers la maîtrise des déploiements Kubernetes. Les choix effectués ici (stratégie, paramètres) serviront de base pour les étapes suivantes (probes, observabilité, stratégies avancées). Prenez le temps de comprendre les mécanismes plutôt que de simplement copier des configurations.