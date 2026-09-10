# ADR-0006: Stratégies de déploiement avancées — Blue/Green et Canary

## Statut

Accepté

## Contexte

L'étape 3 a introduit le déploiement `nginx` avec une stratégie `RollingUpdate` (`maxSurge: 1`, `maxUnavailable: 1`). Cette stratégie remplace progressivement les pods d'une version par ceux d'une nouvelle version, mais elle ne permet pas :

- de basculer **instantanément** l'intégralité du trafic vers une nouvelle version ;
- de **revenir en arrière** en une seule opération atomique ;
- d'exposer une nouvelle version à un **sous-ensemble** du trafic pour l'observer avant généralisation.

L'objectif de cette étape est de mettre en place deux stratégies complémentaires :

- **Blue/Green** : deux environnements identiques (Blue = version actuelle, Green = nouvelle version), bascule du trafic via le `Service`, rollback immédiat.
- **Canary** : déploiement progressif (paliers de réplicas), observation des métriques à chaque palier, décision de continuer ou d'annuler.

Ces stratégies doivent respecter les `ResourceQuota` et `LimitRange` définis à l'étape 5 (ADR-0005) pour les namespaces `dev` et `staging`.

Le brief indique les chemins `stacks/kubernetes/apps/` et `infra/adrs/`. Dans ce dépôt, les étapes précédentes utilisent `stacks/kubernetes/infra/apps/` et `stacks/kubernetes/adrs/`. Les fichiers sont donc créés dans la structure existante, sans déplacement.

## Décision

### 1. Répartition des stratégies par environnement

| Environnement | Stratégie | Justification |
| :--- | :--- | :--- |
| `staging` | **Blue/Green** | Environnement de pré-production : besoin d'une bascule binaire et d'un rollback immédiat avant promotion en production. |
| `dev` | **Canary** | Environnement d'expérimentation : besoin d'observer une nouvelle version sur un sous-ensemble de trafic avant généralisation. |

### 2. Blue/Green en staging

Fichiers :

- `stacks/kubernetes/infra/apps/staging/nginx/deployment-nginx-blue.yaml` — version `1.30.4`, label `track: "blue"`.
- `stacks/kubernetes/infra/apps/staging/nginx/deployment-nginx-green.yaml` — version `1.31.5`, label `track: "green"`.
- `stacks/kubernetes/infra/apps/staging/nginx/service-nginx.yaml` — `Service` partagé, selector `app: nginx`, `environment: staging`, `track: "blue"`.
- `stacks/kubernetes/infra/apps/staging/nginx/switch-deployment-track.sh` — script de bascule et de rollback.

Les deux `Deployment` sont **identiques** en configuration (probes, ressources, securityContext, volumes, replicas `3`). La seule différence est l'image (`1.30.4` vs `1.31.5`) et le label `track`.

Le `Service` sélectionne les pods via `spec.selector.track`. La bascule consiste à modifier ce selector :

```bash
# Bascule blue -> green
kubectl patch -n staging service nginx-service \
  --type='merge' \
  -p '{"spec":{"selector":{"track":"green"}}}'

# Rollback green -> blue
kubectl patch -n staging service nginx-service \
  --type='merge' \
  -p '{"spec":{"selector":{"track":"blue"}}}'
```

Le script `switch-deployment-track.sh` automatise cette bascule : il lit le `track` courant, calcule le `track` cible (`blue` ↔ `green`), lance un pod `curl` continu, applique le patch, puis affiche les logs pour vérifier la continuité de service.

### 3. Canary en dev

Fichiers :

- `stacks/kubernetes/infra/apps/demo/nginx/deployment-nginx.yaml` — version `1.30.4`, label `track: "stable"`.
- `stacks/kubernetes/infra/apps/demo/nginx/deployment-nginx-canary.yaml` — version `1.31.5`, label `track: "canary"`.
- `stacks/kubernetes/infra/apps/demo/nginx/service-nginx.yaml` — `Service` partagé, selector `app: nginx` (sans `track`).
- `stacks/kubernetes/infra/apps/demo/nginx/switch-deployment-canary.sh` — script de progression et d'annulation.

Le `Service` sélectionne les pods via `app: nginx` uniquement, ce qui route le trafic vers **les deux** `Deployment` simultanément. Le ratio de trafic est contrôlé par le **nombre de réplicas** de chaque `Deployment` :

```bash
# Augmenter la part canary
kubectl scale deployment -n dev -l track=canary --replicas 1
kubectl scale deployment -n dev -l track=canary --replicas 2
kubectl scale deployment -n dev -l track=canary --replicas 3

# Annuler complètement le canary
kubectl scale deployment -n dev -l track=canary --replicas 0
```

Le script `switch-deployment-canary.sh` automatise cette progression : il enchaîne les paliers `3/0 → 3/1 → 3/2 → 3/3 → 3/0` (stable/canary), envoie `NB_REQ=1000` requêtes à chaque palier via un pod `curl`, et affiche les pourcentages observés pour chaque version.

### 4. Distinguabilité des versions

Les deux versions répondent différemment sur `/version` grâce à la variable `$nginx_version` exposée par le `ConfigMap` `nginx-config` :

- `1.30.4` (stable / blue)
- `1.31.5` (canary / green)

Cela permet de mesurer objectivement la répartition du trafic dans les scripts de validation.

### 5. Respect des quotas (ADR-0005)

Les `ResourceQuota` du namespace `staging` limitent `count/deployment.apps` à `2`, ce qui correspond exactement aux deux `Deployment` `nginx-blue` et `nginx-green`. Les `requests`/`limits` de chaque conteneur restent dans les bornes du `LimitRange` staging (`cpu max 180m`, `memory max 19Mi`).

## Alternatives considérées

| Alternative | Avantages | Inconvénients | Décision |
| :--- | :--- | :--- | :--- |
| **A – Blue/Green en staging + Canary en dev** (retenue) | Chaque stratégie est appliquée là où elle apporte le plus de valeur : rollback immédiat en pré-prod, observation progressive en dev | Deux mécanismes à maintenir, deux scripts distincts | ✅ Retenue |
| **B – Canary dans les deux environnements** | Un seul mécanisme à maintenir | Pas de rollback binaire en staging, or c'est le besoin principal en pré-production | ❌ Rejetée |
| **C – Blue/Green dans les deux environnements** | Bascule atomique partout | Pas d'observation progressive possible en dev, doublement des ressources à chaque déploiement | ❌ Rejetée |
| **D – Ingress avec poids (ex. NGINX Ingress canary annotations)** | Contrôle fin du pourcentage sans jouer sur les réplicas | Dépendance à un contrôleur Ingress, complexité supplémentaire non requise à cette étape | ❌ Rejetée |
| **E – Service Mesh (Istio, Linkerd)** | Routage pondéré natif, métriques par version | Sur-dimensionné pour l'objectif pédagogique, coût opérationnel élevé | ❌ Rejetée |

## Trade-offs

- **Blue/Green — coût en ressources vs rollback instantané** : maintenir deux `Deployment` complets double la consommation de pods pendant la bascule. En staging, le quota `pods: 6` couvre exactement `3 (blue) + 3 (green)`. Le rollback est une simple modification de selector, donc quasi instantané (aucun redéploiement).

- **Canary — granularité vs précision** : le ratio de trafic est approximé par le nombre de réplicas (`3/1` ≈ 25 %, `3/2` ≈ 40 %, `3/3` = 50 %). Ce n'est pas un pourcentage exact, mais c'est suffisant pour observer une nouvelle version. Un routage pondéré précis nécessiterait un Ingress ou un Service Mesh (alternatives D et E rejetées).

- **Compatibilité avec les ADR précédentes** : les deux stratégies réutilisent les `Deployment` et `Service` de l'étape 3 (ADR-0003) et respectent les quotas de l'étape 5 (ADR-0005). Aucune modification du RBAC (ADR-0002) n'est nécessaire.

## Risques identifiés et mitigations

| Risque | Mitigation |
| :--- | :--- |
| **Quota `count/deployment.apps` en tension** : le namespace `dev` a un quota de `1` mais héberge `2` `Deployment` (`nginx` + `nginx-canary`). Le namespace `staging` a un quota de `2` et héberge exactement `2` `Deployment`. | À arbitrer : soit relever le quota `count/deployment.apps` de `dev` à `2`, soit documenter que le canary est une exception temporaire. **Non tranché dans cet ADR.** |
| **Bascule Blue/Green non atomique au niveau des connexions en cours** : les connexions TCP établies vers les anciens pods ne sont pas coupées, mais les nouvelles requêtes sont routées vers le nouveau `track`. | Acceptable pour un service HTTP sans état. À surveiller si des connexions longues sont introduites. |
| **Canary sans métriques automatiques** : la décision de poursuivre ou d'annuler repose sur une observation manuelle des pourcentages. | Les métriques Prometheus/Grafana (étape 4) permettent d'observer les erreurs et la latence par version. Une automatisation (analyse automatique + rollback) n'est pas implémentée à cette étape. |
| **Dérive de configuration entre blue et green** : les deux `Deployment` doivent rester identiques hors image et label. | Toute modification doit être appliquée aux deux fichiers. Une factorisation via Kustomize (étape 8) réduira ce risque. |
| **Absence de `PodDisruptionBudget`** : déjà signalé à l'étape 4, toujours non implémenté. | À traiter en production. |

## Limites de l'approche

- Le routage Canary par nombre de réplicas est **approximatif** : il ne garantit pas un pourcentage exact de trafic.
- Le Blue/Green **double les ressources** pendant la période de coexistence des deux versions.
- Aucun des deux mécanismes n'est **automatisé** : la bascule et le rollback restent des opérations manuelles déclenchées par un opérateur.
- Le Canary ne dispose pas d'**analyse automatique** des métriques pour décider d'un rollback.

## Références

- Kubernetes Documentation – [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- Kubernetes Documentation – [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- Kubernetes Documentation – [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- ADR-0002 : RBAC et moindre privilège
- ADR-0003 : Déploiements basiques avec RollingUpdate
- ADR-0004 : Probes et observabilité applicative
- ADR-0005 : ResourceQuotas et LimitRanges par namespace
- Manifests : `stacks/kubernetes/infra/apps/staging/nginx/`, `stacks/kubernetes/infra/apps/demo/nginx/`
- Scripts : `switch-deployment-track.sh`, `switch-deployment-canary.sh`
