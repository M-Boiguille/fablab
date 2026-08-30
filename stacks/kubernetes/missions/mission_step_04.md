# Mission Étape 4 — Probes et observabilité applicative

## Objectif

Rendre le déploiement Nginx existant **résilient et observable** : les sondes de santé doivent garantir une disponibilité réelle pendant les mises à jour, et les métriques doivent permettre de détecter une dégradation avant qu'elle n'impacte les utilisateurs.

---

## A. À lire

**Livres et documentation**
- *Kubernetes Patterns*, chapitre **Health Probes** — comprendre la différence fondamentale entre liveness et readiness, et pourquoi les confondre provoque des incidents.
- Documentation Kubernetes : **Configure Liveness, Readiness and Startup Probes** — les paramètres (`initialDelaySeconds`, `periodSeconds`, `failureThreshold`) et leurs pièges.
- Documentation Prometheus : **Querying basics** — savoir écrire une requête qui a du sens, pas seulement copier un exemple.

**Modules KodeKloud**
- CKAD : **Probes** — exercices pratiques sur les trois types de sondes.
- DevOps Monitoring : **Prometheus and Grafana basics** — installation et premiers dashboards.

**Questions à se poser pendant la lecture**
- Que se passe-t-il si une livenessProbe échoue ? Et une readinessProbe ? Pourquoi ne doivent-elles pas être configurées de la même manière ?
- Comment Kubernetes distingue-t-il un pod "pas encore prêt" d'un pod "en panne" ?
- Pourquoi une application peut-elle répondre `200 OK` à une sonde HTTP tout en étant incapable de servir du trafic ?

---

## B. À créer

### 1. Mise à jour du Deployment Nginx — `deployments/nginx-deployment.yaml`

**Exigences**
- Ajouter une **readinessProbe** qui vérifie que Nginx est réellement capable de servir des requêtes (pas seulement "le processus tourne").
- Ajouter une **livenessProbe** qui détecte un état de blocage irrécupérable.
- Choisir des valeurs de délais et de seuils **justifiées** pour une application Nginx qui démarre en quelques secondes — pas de valeurs copiées sans réflexion.
- Les sondes doivent être cohérentes avec la ConfigMap existante : si la configuration change le port ou le chemin, les sondes doivent suivre.

**Critères d'acceptation**
- Les deux sondes sont présentes et utilisent des endpoints différents (ou des méthodes différentes) si les rôles l'exigent.
- Les valeurs de `initialDelaySeconds`, `periodSeconds` et `failureThreshold` sont documentées dans un commentaire avec la justification.
- Aucune sonde ne dépend d'un endpoint qui n'existe pas dans la configuration Nginx actuelle.

### 2. Manifest Prometheus — `monitoring/prometheus.yaml`

**Exigences**
- Déployer Prometheus dans le namespace `tools` (conformément à la décision d'architecture des namespaces).
- Configurer la découverte de cibles pour scraper les pods du namespace `dev` (et `staging` si pertinent).
- Utiliser les annotations standard pour la découverte (`prometheus.io/scrape`, `prometheus.io/port`).
- Ne pas exposer Prometheus en dehors du cluster (pas de NodePort, pas de LoadBalancer).

**Critères d'acceptation**
- Le déploiement Prometheus est fonctionnel et accessible via port-forward.
- Les targets apparaissent dans l'interface Prometheus avec l'état `UP` pour les pods Nginx.
- La configuration de scraping est versionnée dans le repo, pas modifiée à la main dans le pod.

### 3. Manifest Grafana — `monitoring/grafana.yaml`

**Exigences**
- Déployer Grafana dans le namespace `tools`.
- Configurer la source de données Prometheus (via un ConfigMap ou une variable d'environnement).
- Créer un dashboard nommé **"Nginx Overview"** avec au minimum :
  - Le nombre de pods prêts / non prêts
  - Le taux de requêtes HTTP (si les métriques Nginx sont disponibles) ou à défaut le CPU/mémoire des pods
  - Une alerte visuelle quand un pod n'est pas prêt depuis plus de 2 minutes

**Critères d'acceptation**
- Le dashboard est provisionné automatiquement (pas de configuration manuelle dans l'interface Grafana).
- La source de données pointe vers le service Prometheus du namespace `tools`.
- Le dashboard est exportable en JSON et versionné dans le repo.

### 4. Script de validation — `tests/step_04_validation.sh`

**Exigences**
- Vérifier que les sondes sont présentes dans le Deployment (readiness ET liveness).
- Vérifier que Prometheus et Grafana sont déployés dans le namespace `tools`.
- Vérifier que les pods Nginx sont tous `Ready` après l'ajout des sondes.
- Vérifier que le script produit un fichier `tests/step_04_result.txt` contenant `PASS` ou `FAIL` avec le détail des vérifications.
- Le script doit être **exécutable** (`chmod +x`) et **reproductible** (peut être relancé sans effet de bord).

**Critères d'acceptation**
- Le script retourne un code de sortie `0` si toutes les vérifications passent, `1` sinon.
- Le fichier `tests/step_04_result.txt` est généré avec un horodatage et la liste des vérifications effectuées.
- Le script n'utilise que `kubectl` et des commandes standard (pas de plugin spécifique).

### 5. ADR final — `infra/adrs/adr_step_04_final.md`

**Exigences**
- Documenter les décisions prises concernant :
  - Le choix des endpoints et des paramètres des sondes
  - Le choix de Prometheus/Grafana comme stack d'observabilité (vs Datadog, New Relic, etc.)
  - Le périmètre de ce qui est monitoré à cette étape (et ce qui ne l'est pas encore)
- Mentionner les alternatives envisagées et pourquoi elles ont été écartées.
- Lister les risques résiduels et ce qui devra être traité aux étapes suivantes.

**Critères d'acceptation**
- L'ADR suit la structure standard : Contexte, Décision, Conséquences, Alternatives envisagées.
- Chaque décision est justifiée par un fait ou une contrainte, pas une préférence personnelle.
- L'ADR mentionne explicitement le risque métier identifié (voir section "Risque métier" ci-dessous).

---

## C. À livrer

### Preuves attendues

1. **Fichiers modifiés/créés** dans le repo :
   - `deployments/nginx-deployment.yaml` (modifié avec les sondes)
   - `monitoring/prometheus.yaml`
   - `monitoring/grafana.yaml`
   - `monitoring/dashboards/nginx-overview.json` (dashboard Grafana provisionné)
   - `tests/step_04_validation.sh`
   - `tests/step_04_result.txt` (généré par le script)
   - `infra/adrs/adr_step_04_final.md`

2. **Démonstration en direct** (ou capture d'écran horodatée) :
   - `kubectl get pods -n dev` montrant tous les pods `Running` et `Ready`
   - `kubectl port-forward -n tools svc/prometheus 9090:9090` avec capture montrant les targets `UP`
   - `kubectl port-forward -n tools svc/grafana 3000:3000` avec capture du dashboard "Nginx Overview"

### Commandes de validation

```bash
# Vérifier que les sondes sont bien configurées
kubectl get deployment nginx -n dev -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' | jq .
kubectl get deployment nginx -n dev -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' | jq .

# Vérifier que tous les pods sont prêts
kubectl get pods -n dev -l app=nginx

# Vérifier que Prometheus et Grafana tournent
kubectl get pods -n tools -l app=prometheus
kubectl get pods -n tools -l app=grafana

# Lancer la validation complète
./tests/step_04_validation.sh
cat tests/step_04_result.txt
```

### Marqueurs de réussite

- [ ] Les pods Nginx ont une readinessProbe ET une livenessProbe, et tous les pods sont `Ready`.
- [ ] Une simulation de panne (ex: `kubectl exec` pour corrompre la config Nginx) fait passer le pod en `Unready` sans le redémarrer en boucle.
- [ ] Prometheus scrappe les métriques des pods Nginx (targets `UP`).
- [ ] Grafana affiche un dashboard avec les métriques Nginx et une alerte configurée.
- [ ] Le script `tests/step_04_validation.sh` passe avec `PASS` dans `tests/step_04_result.txt`.
- [ ] L'ADR documente les décisions et les alternatives écartées.

---

## Risque métier

**Scénario :** L'équipe marketing lance une campagne avec un pic de trafic attendu. Le déploiement actuel n'a aucune sonde : si Nginx se bloque (processus vivant mais incapable de servir), Kubernetes continue d'envoyer du trafic vers un pod mort. Résultat : 30% des utilisateurs voient une erreur 502 pendant la campagne, sans qu'aucune alerte ne soit déclenchée. L'impact est direct sur le chiffre d'affaires et la confiance des utilisateurs.

**Ce que cette étape doit éviter :** ce scénario, en garantissant que les pods incapables de servir sont retirés du Service automatiquement, et que l'équipe est alertée avant que l'impact ne devienne visible pour les utilisateurs.

---

## Estimation de temps

| Activité | Durée estimée |
|---|---|
| Lecture et compréhension des concepts (probes, Prometheus) | 2-3 heures |
| Configuration des sondes sur le Deployment existant | 1-2 heures |
| Déploiement Prometheus et Grafana (manifests, configuration) | 3-4 heures |
| Création du dashboard Grafana provisionné | 2-3 heures |
| Écriture du script de validation et tests | 2-3 heures |
| Rédaction de l'ADR | 1-2 heures |
| **Total** | **11-17 heures** (≈ 2 jours ouvrés) |

---

## Rappel des contraintes

- **Ne pas fournir** le contenu des manifests, le script de validation ou le texte de l'ADR — uniquement les exigences et critères.
- **Ne pas anticiper** les étapes 5 et suivantes (ResourceQuotas, stratég