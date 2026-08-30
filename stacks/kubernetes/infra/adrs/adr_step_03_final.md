# ADR - Étape 03 : Déploiement basique avec RollingUpdate

## Contexte

Une application web simple basée sur Nginx doit être déployée dans le namespace `dev`.

Le déploiement doit permettre de maintenir plusieurs instances de l'application et de réaliser des mises à jour progressives afin de limiter les interruptions de service.

La configuration Nginx doit également être découplée de l'image du conteneur afin de ne pas dépendre du filesystem du nœud Kubernetes hébergeant le Pod.

## Décision

### Deployment

Un `Deployment` est utilisé afin de gérer de manière déclarative le nombre de Pods souhaité ainsi que leur cycle de vie et leurs mises à jour.

Trois replicas sont configurés afin de disposer de plusieurs instances simultanément et de conserver une capacité de service lorsqu'une instance devient temporairement indisponible.

### RollingUpdate

La stratégie `RollingUpdate` est retenue afin de remplacer progressivement les anciennes instances par les nouvelles lors d'une mise à jour, plutôt que de supprimer toutes les instances avant de recréer les nouvelles.

Les paramètres suivants sont utilisés :

```yaml
replicas: 3

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

Avec trois replicas, `maxUnavailable: 1` autorise au maximum un Pod indisponible pendant le rollout. `maxSurge: 1` autorise temporairement un seul Pod supplémentaire par rapport au nombre de replicas souhaites.

Ce choix privilegie la disponibilité tout en limitant la consommation temporaire de ressources.

### Service

Un Service de type `ClusterIP` est utilisé pour fournir un point d'accès réseau stable à l'application depuis le cluster.

Le Service écoute sur le port `8080` et transmet les requêtes vers le port `80` des Pods :

```text
Service :8080 → Pod :80
```

Le Service utilise le même selector que les labels du Deployment afin que Kubernetes associe automatiquement les Pods correspondants aux endpoints du Service.

Le choix de `ClusterIP` limite l'exposition directe de cette application au réseau du cluster. Aucune exposition externe n'est requise pour cette application de démonstration.

### ConfigMap

La configuration Nginx est stockée dans un `ConfigMap` et montée dans le conteneur sous `/etc/nginx/conf.d/default.conf`.

Ce choix permet de découpler la configuration de l'image du conteneur et du filesystem du nœud Kubernetes. La configuration reste ainsi disponible lorsqu'un Pod est replanifié sur un autre nœud.

La configuration contient notamment les routes `/health` et `/hello`, utilisées pour vérifier le fonctionnement de l'application.

### Image

L'image `nginx:1.30.4` est utilisée avec une version explicitement définie afin d'éviter qu'une nouvelle version de l'image soit implicitement récupérée lors de la recréation des Pods.

## Alternatives considérées

### Deployment avec stratégie Recreate

**Pour :**

* Garantit que les anciennes instances sont supprimées avant la création des nouvelles.
* Peut être adapté à des applications dont plusieurs versions ne peuvent pas fonctionner simultanément.

**Contre :**

* Les anciennes instances sont supprimées avant la création des nouvelles.
* Peut provoquer une interruption de service pendant le déploiement.

Cette stratégie n'a pas été retenue car la disponibilité pendant les mises à jour est privilégiée.

### Pod unique

**Pour :**

* Configuration initiale simple.
* Consommation de ressources limitée.

**Contre :**

* Absence de redondance.
* Le Pod constitue un point de défaillance unique (SPOF).
* Les mises à jour et opérations de maintenance sont moins adaptées à une gestion déclarative.

Cette solution n'a pas été retenue car elle ne permet pas de bénéficier de plusieurs instances de l'application.

### Service NodePort

**Pour :**

* Permet d'accéder au Service depuis l'extérieur du cluster via un port exposé sur les nœuds.

**Contre :**

* Augmente la surface d'exposition réseau.
* Nécessite de gérer les règles réseau et firewall associées.
* Cette exposition externe n'est pas nécessaire pour l'application actuelle.

Un `ClusterIP` a donc été préféré.

### Configuration via `hostPath`

**Pour :**

* Permet de monter directement un fichier présent sur le filesystem du nœud.

**Contre :**

* La configuration devient dépendante du filesystem du nœud hébergeant le Pod.
* Le fichier doit être présent sur chaque nœud susceptible d'héberger le Pod.
* Une replanification vers un nœud ne disposant pas du fichier peut empêcher le Pod de démarrer.

Le `ConfigMap` a donc été retenu afin de découpler la configuration du nœud.

### Configuration intégrée à l'image

**Pour :**

* Configuration directement disponible avec l'image.
* Pas de ressource Kubernetes supplémentaire à gérer.

**Contre :**

* Couple la configuration applicative à l'image du conteneur.
* Toute modification de configuration nécessite généralement de reconstruire et redéployer l'image.
* Réduit la séparation entre artefact applicatif et configuration de déploiement.

Le `ConfigMap` a été préféré afin de conserver cette séparation.

## Trade-offs

### Disponibilité vs consommation de ressources

Le choix de `maxUnavailable: 1` et `maxSurge: 1` favorise la disponibilité pendant les mises à jour tout en limitant la consommation temporaire de ressources.

En contrepartie, jusqu'à quatre Pods peuvent temporairement etre presents pour trois replicas souhaites. Le cluster doit donc disposer d'une marge suffisante en CPU et en memoire pour absorber cette consommation temporaire.

### Ressources du conteneur

Les valeurs initiales de CPU et de mémoire sont des estimations adaptées à cette application de démonstration.

Dans un environnement réel, les `requests` et `limits` devront être dimensionnés à partir de la consommation observée et de la charge attendue, avec une marge suffisante.

### Exposition réseau

Le choix de `ClusterIP` limite l'exposition directe de l'application au réseau du cluster. Une exposition externe nécessiterait ultérieurement un mécanisme adapté tel qu'un `Ingress`, un `LoadBalancer` ou, selon le besoin, un `NodePort`.

### Gestion de la configuration

Le `ConfigMap` apporte une séparation claire entre l'image Nginx et sa configuration. En contrepartie, il faut gérer les mises à jour de la configuration et le redémarrage ou rollout des Pods lorsque cela est nécessaire pour que les modifications soient prises en compte.

## Ajustements opérationnels et amendements des ADR précédentes

Lors de la revue SRE de l'étape 03, plusieurs points ont ete souleves. Les decisions suivantes ont ete prises pour l'exercice, avec des notes de report en production.

### Amendement de l'ADR step 02 — RBAC

Le role `developer` (ClusterRole) conservant l'acces en ecriture aux `secrets` dans `dev` et `staging` reste conforme a la mission de l'etape 02. Cette decision est maintenue pour l'homologation, avec la connaissance qu'en production on privilegierait des `Role` namespace-scoped dedies et retirerait `secrets` du perimetre applicatif.

### Image et supply chain

L'image `nginx:1.30.4` est epinglee par digest :

```text
nginx:1.30.4@sha256:09cc2702709e6388d979d8030e3ab4eb1ceb699b2dced26d7543e872a822e823
```

`imagePullPolicy: IfNotPresent` est utilise en dev avec un digest epingle : l'image est utilisee si deja presente, sinon elle est tiree. Le digest garantit l'immutabilite. En production, on utilisera un registre prive approuve et des tags immuables.

### Securite du conteneur

Les controles suivants sont appliques au Pod et au conteneur :

- `runAsNonRoot: true`
- `runAsUser: 101`
- `fsGroup: 101`
- `allowPrivilegeEscalation: false`
- `capabilities: drop: - ALL`

### Probes

- `livenessProbe` et `readinessProbe` sur `/health` port `80`.
- `livenessProbe` : `periodSeconds: 10`
- `readinessProbe` : `periodSeconds: 5`

### Reseau et Service

- ConfigMap Nginx : `listen 80`
- Service : `port: 8080`, `targetPort: 80`, `protocol: TCP`
- `publishNotReadyAddresses: false` par defaut

### Labels

Les labels suivants sont appliques aux ressources :

```yaml
app: nginx
environment: dev
team: platform
version: "1.30.4"
managed-by: terraform
```

### RollingUpdate

`maxSurge: 1` est retenu pour limiter la consommation temporaire de ressources, tout en maintenant la disponibilite.

### Points non traites dans cet exercice

Les elements suivants sont reconnus comme necessaires en production, mais reportes a des etapes ulterieures :

- Registre prive / signature Cosign
- PodDisruptionBudget
- `readOnlyRootFilesystem` (necessite des volumes de cache et de logs)
- Annotations de version sur le ConfigMap

## Références

- CKA (KodeKloud)
- Kubernetes (Dunod)
