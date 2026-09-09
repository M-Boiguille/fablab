# ADR-0005: ResourceQuotas et LimitRanges par namespace

## Statut

Accepté

## Contexte

Nous devons protéger le cluster Kubernetes contre les consommations excessives de ressources. Sans mécanisme de gouvernance, une application mal configurée ou défaillante pourrait consommer l’intégralité des ressources d’un nœud, voire du cluster, provoquant un déni de service et une dégradation significative des performances pour les autres applications.

L’objectif de cette étape est de créer des `ResourceQuota` et des `LimitRange` pour les namespaces `dev`, `staging`, `prod` et `tools`, avec des valeurs différenciées selon l’environnement. 

Ces mécanismes doivent être complétés par une gouvernance des ressources afin de garantir la stabilité et la disponibilité de l’ensemble.

Les chemins de livraison indiqués dans le brief sont `kubernetes/namespaces/<namespace>/`. Toutefois, dans ce dépôt, les précédentes étapes utilisent une organisation sous `stacks/kubernetes/infra/base/`. 

## Décision

### 1. Création des nouveaux fichiers sans déplacement

Les fichiers suivants seront créés dans la structure existante :

- `stacks/kubernetes/infra/base/resource_quotas/resourcequota_dev.yaml`
- `stacks/kubernetes/infra/base/resource_quotas/resourcequota_staging.yaml`
- `stacks/kubernetes/infra/base/resource_quotas/resourcequota_prod.yaml`
- `stacks/kubernetes/infra/base/resource_quotas/resourcequota_tools.yaml`
- `stacks/kubernetes/infra/base/limit_ranges/limitrange_dev.yaml`
- `stacks/kubernetes/infra/base/limit_ranges/limitrange_staging.yaml`
- `stacks/kubernetes/infra/base/limit_ranges/limitrange_prod.yaml`
- `stacks/kubernetes/infra/base/limit_ranges/limitrange_tools.yaml`

Ces fichiers sont intégrés à la base Kustomize existante afin d’être appliqués automatiquement avec les autres ressources des namespaces.

### 2. Objectifs des quotas et limites

- **ResourceQuota** : limiter le nombre total de ressources CPU, mémoire, pods et services par namespace.
- **LimitRange** : imposer des valeurs par défaut, minimales et maximales aux conteneurs qui ne déclarent pas explicitement leurs `requests` et `limits`.

Ces mécanismes complètent les décisions précédentes.

### 3. Valeurs retenues

Les valeurs retenues pour les `ResourceQuota` sont les suivantes :

#### ResourceQuota par namespace

| Namespace | `requests.cpu` | `requests.memory` | `limits.cpu` | `limits.memory` | `pods` | `services` | `count/deployment.apps` |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `dev` | `300m` | `40Mi` | `700m` | `96Mi` | `5` | `1` | `1` |
| `staging` | `1080m` | `114Mi` | `1080m` | `114Mi` | `6` | `2` | `2` |
| `prod` | `1512m` | `161Mi` | `1512m` | `161Mi` | `7` | `2` | `2` |
| `tools` | `600m` | `768Mi` | `1` | `1Gi` | `4` | — | — |

Le namespace `tools` ne comporte pas de limite sur le nombre de services ni sur le nombre de déploiements, car il est destiné à héberger des outils d’observabilité et de gestion.

#### LimitRange par namespace

| Namespace | CPU defaultRequest | CPU default | CPU min | CPU max | Mémoire defaultRequest | Mémoire default | Mémoire min | Mémoire max |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `dev` | `50m` | `100m` | `10m` | `150m` | `6Mi` | `12Mi` | `4Mi` | `16Mi` |
| `staging` | `60m` | `120m` | `12m` | `180m` | `7Mi` | `14Mi` | `5Mi` | `19Mi` |
| `prod` | `72m` | `144m` | `14m` | `216m` | `8Mi` | `17Mi` | `6Mi` | `23Mi` |
| `tools` | `50m` | `100m` | `10m` | `600m` | `64Mi` | `128Mi` | `4Mi` | `768Mi` |

Le namespace `tools` définit des valeurs minimales et maximales adaptées aux outils variés (min `10m`/`4Mi`, max `600m`/`768Mi`).

### 4. Mise en œuvre dans le repository

Les fichiers sont placés dans `stacks/kubernetes/infra/base/` et référencés dans les kustomizations correspondantes. Les namespaces `dev`, `staging`, `prod` et `tools` disposent déjà de leurs kustomizations. L’ajout des `ResourceQuota` et `LimitRange` ne modifie pas la structure existante.

## Alternatives considérées

| Alternative | Avantages | Inconvénients | Décision |
| :--- | :--- | :--- | :--- |
| **A – ResourceQuota + LimitRange par namespace** (retenue) | Contrôle fin par environnement, aligné sur la structure du dépôt, évolutif | Multiplication des fichiers de configuration | ✅ Retenue |
| **B – Quotas globaux au niveau du cluster** | Configuration unique | Pas de différenciation par environnement, risque de sur-contraindre le `prod` ou de sous-contraindre le `dev` | ❌ Rejetée |
| **C – Aucun quota, uniquement des LimitRanges** | Simplicité | Ne protège pas contre l’épuisement global des ressources d’un namespace | ❌ Rejetée |
| **D – Utiliser des `LimitRange` applicatifs dans chaque déploiement** | Proximité avec l’application | Responsabilité déléguée aux équipes applicatives, impossible à auditer globalement | ❌ Rejetée |

## Trade-offs

- **Granularité vs maintenance** : Le choix de quotas par namespace offre une protection fine mais augmente le nombre de fichiers à maintenir. Cette charge est acceptable car la structure `infra/base` permet de centraliser et versionner ces objets.

- **Valeurs conservatrices vs flexibilité** : Les valeurs choisies limitent volontairement la consommation pour éviter toute dégradation. Elles peuvent entraver un déploiement légitime si la charge réelle dépasse les limites. Une revue régulière des métriques (ADR-0004) permettra d’ajuster ces seuils.

- **Compatibilité avec les ADR précédentes** : Les quotas n’interfèrent pas avec le RBAC (ADR-0002) ni avec la stratégie de déploiement (ADR-0003). Ils s’appliquent au niveau du namespace et non aux ressources individuelles, ce qui préserve la séparation des responsabilités.

## Références

- Kubernetes Documentation – [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- Kubernetes Documentation – [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
