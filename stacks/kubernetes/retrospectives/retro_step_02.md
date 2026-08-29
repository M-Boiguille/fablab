# Rétrospective - Étape 2 : RBAC et moindre privilège

**Date** : [Date de la rétrospective]  
**Participants** : Équipe plateforme Fablab  
**Périmètre** : Modélisation des accès RBAC pour les équipes Dev, QA, SRE et CI/CD

---

## 1. Ce qui s'est bien passé

### ✅ Modèle DRY adopté avec succès
Le choix du **ClusterRole + RoleBindings** pour les développeurs et le CI/CD a permis de définir une seule règle pour `dev` et `staging`, évitant la duplication de manifests et réduisant la charge de maintenance. La validation automatisée a confirmé que les permissions sont correctement appliquées sur les deux environnements.

### ✅ Séparation stricte des responsabilités
La distinction entre les **SRE applicatifs** (RoleBinding dans `prod`) et les **SRE cluster** (ClusterRoleBinding pour `nodes` et `persistentvolumes`) respecte le modèle de sécurité Kubernetes. Cette séparation évite toute sur-permission et a été validée par les tests.

### ✅ CI/CD correctement restreint
Les ServiceAccounts `ci-cd-dev` et `ci-cd-staging` disposent de droits minimaux (`create`/`update` sur `deployments` et `services` uniquement). L'absence totale d'accès à `prod` est conforme à la stratégie de déploiement manuel/GitOps.

---

## 2. Ce qui a été difficile

### ⚠️ Compréhension des subtilités RoleBinding vs ClusterRoleBinding
La contrainte technique selon laquelle un `RoleBinding` ne peut pas accorder de droits sur des ressources cluster-scoped (`nodes`, `persistentvolumes`) a nécessité une phase d'apprentissage. Il a fallu concevoir un **double objet** pour les SRE, ce qui a initialement créé de la confusion dans l'équipe.

### ⚠️ Gestion des permissions `delete` et `exec`
L'interdiction explicite de `delete` sur les pods pour les développeurs, tout en l'autorisant pour les SRE en `prod`, a demandé une réflexion approfondie sur les besoins réels de chaque rôle. Le risque de sur-permission était réel et a nécessité plusieurs itérations.

---

## 3. Leçons apprises

### 📌 Le moindre privilège est un équilibre, pas une règle absolue
Le principe du moindre privilège ne signifie pas "aucun droit", mais "les droits strictement nécessaires". L'exemple des SRE en `prod` (avec `delete` et `exec`) illustre qu'il faut adapter les permissions aux besoins opérationnels, tout en les limitant au périmètre requis.

### 📌 La mutualisation des règles a un coût en termes de risque partagé
Le choix du `ClusterRole` pour `dev` et `staging` simplifie la maintenance mais implique qu'une modification impacte les deux environnements simultanément. Ce trade-off est acceptable en homologation, mais il faut **documenter explicitement** ce risque pour les futurs changements.

### 📌 Les groupes SSO sont la clé d'une gestion durable
L'utilisation de groupes (`developer-grp`, `qa-grp`, `sre-grp`) plutôt que d'utilisateurs individuels dans les `subjects` permet une révocation centralisée via le SSO. Cette décision évite de modifier les manifests Kubernetes à chaque arrivée/départ.

---

## 4. Risque reporté

### 🔴 Dérive des permissions CI/CD vers `prod`

**Description** : Le CI/CD n'a actuellement aucun accès à `prod`, mais la tentation sera forte d'automatiser les déploiements en production pour gagner en rapidité. Si un accès est ajouté sans garde-fou, cela pourrait compromettre la stabilité de l'environnement de production.

**Mitigation esquissée** :
- Imposer une **revue systématique** de toute modification des permissions CI/CD (PR obligatoire avec validation SRE)
- Mettre en place un **audit trimestriel** des `RoleBindings` pour détecter toute dérive
- Prévoir une **procédure GitOps** pour `prod` (étape 7 du parcours) avec synchronisation manuelle, afin de conserver un contrôle humain sur les déploiements critiques

---

## 5. Conseil pour la prochaine étape

### 🎯 Anticiper les besoins de `prod` dans les Deployments

Pour l'étape 3 (Déploiements basiques avec RollingUpdate), il est recommandé de **préparer dès maintenant les manifests pour `prod`** avec les mêmes standards que `dev`/`staging`, même si le déploiement en production reste manuel. Cela permettra de :
- Valider la cohérence des configurations entre environnements
- Faciliter la transition vers GitOps à l'étape 7
- Éviter de devoir adapter les manifests en urgence lors de la mise en production

---

## 6. Décisions clés

| Décision | Justification | Impact |
| :--- | :--- | :--- |
| **ClusterRole + RoleBindings** pour Dev et CI/CD | Mutualisation des règles (DRY) pour `dev` et `staging` | Maintenance simplifiée, risque partagé entre environnements |
| **Roles distincts par namespace** pour QA et SRE applicatif | Isolation stricte des permissions par environnement | Plus de manifests, mais moindre privilège absolu |
| **ClusterRoleBinding** pour SRE cluster | Accès aux ressources cluster-scoped (`nodes`, `persistentvolumes`) | Nécessite un objet séparé, mais respecte le modèle Kubernetes |
| **Groupes SSO** comme subjects | Révocation centralisée via SSO, pas de modification des manifests | Gestion durable des accès, audit simplifié |
| **ServiceAccounts dédiés par environnement** pour CI/CD | Isolation stricte des pipelines, aucun accès croisé | Sécurité renforcée, mais multiplication des comptes |
| **Aucun accès CI/CD à `prod`** | Déploiement manuel ou GitOps pour la production | Contrôle humain sur les déploiements critiques |

---

## Annexe : Validation technique

La validation automatisée (28 tests) a confirmé :
- ✅ **Développeurs** : accès `dev`/`staging` conformes, interdictions respectées (`delete`, `prod`, `tools`, création de roles)
- ✅ **QA** : lecture seule stricte dans `staging`, aucune action d'écriture
- ✅ **SRE** : droits étendus dans `prod` uniquement, lecture seule sur les ressources cluster
- ✅ **CI/CD** : droits minimaux sur `deployments`/`services` dans `dev`/`staging`, aucun accès à `prod`

---

*Rétrospective rédigée par l'équipe plateforme Fablab - Prochaine étape : Déploiements basiques avec RollingUpdate*