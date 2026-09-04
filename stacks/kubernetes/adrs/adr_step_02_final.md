# ADR - Étape 02 : RBAC et moindre privilège

## Contexte
https://github.com/M-Boiguille/fablab/pull/3#issue-5282723309

Notre plateforme Fablab doit isoler les accès par environnement (dev, staging, prod, tools) tout en mutualisant la gestion des permissions pour les équipes transverses (Dev, QA, SRE) et les pipelines CI/CD. L'objectif est d'appliquer le principe du moindre privilège sans complexifier inutilement la maintenance.

## Décision

### Modèle général
Nous utilisons des **ClusterRoles** (définition des permissions) associés à des **RoleBindings** par namespace pour les ressources applicatives. Ce modèle mutualise la définition des règles (DRY) tout en restreignant leur portée aux seuls namespaces ciblés.

### Cas particuliers

| Équipe / Acteur | Mécanisme RBAC | Justification |
| :--- | :--- | :--- |
| **Developers** | `ClusterRole` + `RoleBindings` dans `dev` et `staging` | Une seule règle à maintenir pour les deux environnements d'homologation. Interdiction explicite de `delete` sur les pods. |
| **QA** | `Role` (namespace) + `RoleBinding` dans `staging` | Lecture seule stricte (`get`, `list`, `watch`) sur pods, services, configmaps, et logs. Pas de `secrets`. |
| **SRE (ressources applicatives)** | `Role` (namespace `prod`) + `RoleBinding` | Droits étendus (`delete`, `exec`, gestion des `events` et `resourcequotas`) mais limités à `prod`. |
| **SRE (ressources cluster)** | `ClusterRole` + `ClusterRoleBinding` (sans namespace) | Lecture seule sur `nodes` et `persistentvolumes`. **Contrainte technique** : un `RoleBinding` ne peut pas donner de droits sur des ressources cluster-scoped. |
| **CI/CD** | `ClusterRole` + `RoleBindings` dans `dev` et `staging` | Droit de `create` et `update` sur `deployments` et `services` uniquement. ServiceAccounts dédiés par environnement (`ci-cd-dev`, `ci-cd-staging`). **Aucun accès à `prod`** (déploiement manuel ou GitOps). |

## Alternatives considérées

| Alternative | Avantages | Inconvénients | Décision |
| :--- | :--- | :--- | :--- |
| **A – ClusterRole + RoleBindings** (retenue) | Gestion centralisée, DRY, évolutif | Une modification impacte `dev` et `staging` simultanément | ✅ Retenue pour les Devs et le CI/CD |
| **B – Roles distincts par namespace** | Moindre privilège absolu, isolation stricte | Double maintenance, risque d'asymétrie entre environnements | ❌ Rejetée (lourdeur administrative) |
| **C – ClusterRoleBindings globaux** | Simplicité extrême | Accord des droits sur **tous** les namespaces, y compris `prod` et `tools` | ❌ Rejetée (violation du moindre privilège) |

## Trade-offs

- **Simplicité vs risque partagé** : Le choix du `ClusterRole` + `RoleBindings` simplifie la maintenance au prix d'un risque : toute modification de la règle impacte simultanément `dev` et `staging`. Ce trade-off est acceptable en environnement d'homologation/staging partagé, où les deux environnements ont des exigences de sécurité voisines.

- **Double objet pour le SRE** : L'architecture SRE nécessite deux objets distincts (`RoleBinding` pour les ressources namespace, `ClusterRoleBinding` pour les ressources cluster). Cela alourdit légèrement la gestion mais respecte strictement le modèle de sécurité de Kubernetes et évite toute sur-permission en liant des droits globaux à un namespace.

## Gouvernance et cycle de vie des accès

Pour assurer une gestion durable des droits, nous mettons en place :

1. **Authentification fédérée (SSO/OIDC)** : Les `subjects` des `RoleBindings` sont des **groupes SSO** (`developer-grp`, `qa-grp`, `sre-grp`) et non des utilisateurs individuels. La révocation d'un utilisateur se fait au niveau du SSO, sans impact sur les manifests Kubernetes.

2. **Accès temporaires** : Pour les interventions exceptionnelles, des `RoleBindings` éphémères seront créés avec un TTL et supprimés automatiquement (script CronJob ou `kube-rbac-proxy`).

3. **Revue périodique** : Un audit trimestriel listera tous les `RoleBindings` et leurs `subjects` pour détecter les groupes orphelins ou les permissions obsolètes.

4. **Sécurisation du namespace `tools`** : Les ServiceAccounts CI/CD sont strictement limités à leurs environnements cibles. Aucun compte unique ne possède des droits sur plusieurs namespaces de production. Les déploiements en `prod` sont exclus du pipeline automatisé (déclenchement manuel ou GitOps avec synchronisation manuelle).

## Références

- Kubernetes (Dunod) – Chapitre RBAC
- Documentation Kubernetes officielle – [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- Modules KodeKloud – CKA : Role-Based Access Control (RBAC)
- Kubernetes API Reference – [RoleBinding vs ClusterRoleBinding](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#rolebinding-and-clusterrolebinding)

---

*Démarche tutorée par l'IA : l'assistant valide ma compréhension par un échange socratique ; l'intégralité des choix d'architecture et du code final relève de mon seul arbitrage.*
