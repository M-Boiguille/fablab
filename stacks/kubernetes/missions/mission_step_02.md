# Mission Étape 2 — RBAC et moindre privilège

## Objectif

Modéliser les accès des développeurs, QA, SREs et services via des Roles, ClusterRoles et Bindings, en appliquant le principe du moindre privilège.

---

## 📚 A lire

**Livres et documentation :**
- Kubernetes Security, chapitre RBAC
- Documentation Kubernetes : "Using RBAC Authorization"
- Best practices : éviter les ClusterRole sauf pour les opérateurs cluster

**Modules KodeKloud :**
- CKA : Role-Based Access Control (RBAC)
- CKA : ServiceAccounts

---

## 🛠️ A créer

### 1. Manifest RBAC — `infra/rbac/`

Créez les manifests YAML pour les rôles et bindings suivants :

| Artefact | Exigences | Critères d'acceptation |
|----------|-----------|------------------------|
| **Role développeur** (par namespace) | Accès limité aux ressources applicatives (pods, deployments, services, configmaps, secrets) dans les namespaces dev et staging | — Ne peut PAS supprimer de pods<br>— Ne peut PAS accéder aux namespaces prod et tools<br>— Ne peut PAS créer/modifier des Roles ou RoleBindings |
| **Role QA** (par namespace) | Accès en lecture sur les ressources applicatives + logs | — Lecture seule sur pods, deployments, services, configmaps<br>— Peut lire les logs des pods<br>— Aucun droit d'écriture |
| **Role SRE** (par namespace) | Accès complet sur les ressources applicatives + gestion des pods (delete, exec) | — Peut supprimer et exécuter des commandes dans les pods<br>— Peut gérer les events et resourcequotas<br>— Ne peut PAS modifier les rôles et bindings |
| **ClusterRole SRE** | Accès limité aux ressources cluster (nodes, persistentvolumes) en lecture | — Lecture seule sur nodes et persistentvolumes<br>— Aucun droit d'écriture au niveau cluster |
| **ServiceAccount CI/CD** | Compte de service dédié pour les pipelines | — Peut créer/mettre à jour des deployments et services dans dev et staging<br>— Ne peut PAS accéder à prod<br>— Utilisé par les pipelines CI/CD |

### 2. Script de validation — `tests/step_02_validation.sh`

Créez un script bash qui vérifie automatiquement les critères suivants :

| Exigence | Critère de validation |
|----------|----------------------|
| **Existence des ressources** | Tous les Roles, ClusterRoles, RoleBindings et ClusterRoleBindings sont présents |
| **Permissions développeur** | Le rôle développeur ne permet PAS de supprimer des pods (vérification via `kubectl auth can-i`) |
| **Permissions QA** | Le rôle QA permet la lecture mais PAS l'écriture sur les deployments |
| **Permissions SRE** | Le rôle SRE permet la suppression de pods mais PAS la modification des rôles |
| **ServiceAccount CI/CD** | Le ServiceAccount existe et a les permissions attendues dans dev/staging mais PAS dans prod |
| **Moindre privilège** | Aucun rôle n'accorde de droits superflus (vérification manuelle des verbes accordés) |

### 3. ADR — `infra/adrs/adr_step_02_final.md`

Rédigez une décision d'architecture documentant :

| Exigence | Critère d'acceptation |
|----------|----------------------|
| **Contexte** | Rappel de la situation (4 namespaces, besoin de séparer les accès) |
| **Décision** | Choix des modèles RBAC (Role vs ClusterRole, RoleBinding vs ClusterRoleBinding) et justification |
| **Alternatives** | Comparaison avec d'autres approches (ex : un seul ClusterRole pour tous, RBAC par groupe LDAP, etc.) |
| **Conséquences** | Impact sur la sécurité, l'exploitation et les évolutions futures |

---

## 📦 A livrer

### Preuves attendues

1. **Fichiers manifests** dans `infra/rbac/` (Roles, ClusterRoles, Bindings, ServiceAccount)
2. **Script de validation** `tests/step_02_validation.sh` exécutable
3. **Fichier de résultat** `tests/step_02_result.txt` contenant la sortie du script
4. **ADR** `infra/adrs/adr_step_02_final.md` documentant la décision

### Commandes de validation

```bash
# Exécution du script de validation
./tests/step_02_validation.sh

# Vérification manuelle (exemples)
kubectl get roles,rolebindings -n dev
kubectl get clusterroles,clusterrolebindings
kubectl auth can-i --list --as=system:serviceaccount:dev:ci-cd -n dev
```

### Marqueurs de réussite

- ✅ Le script de validation se termine avec le message `PASS`
- ✅ Le fichier `tests/step_02_result.txt` contient `PASS`
- ✅ L'ADR est rédigé et justifie les choix
- ✅ Aucun rôle n'accorde plus de permissions que nécessaire (revue manuelle)

---

## ⚠️ Risque métier

**Scénario à risque :** Un développeur avec des permissions trop larges (ex : suppression de pods en production) pourrait accidentellement interrompre un service critique, entraînant une indisponibilité pour les clients et une perte de revenus. À l'inverse, des permissions trop restrictives pour les SREs pourraient ralentir la résolution d'incidents en production.

---

## ⏱️ Estimation de temps

| Activité | Durée estimée |
|----------|---------------|
| Lecture et compréhension RBAC | 2-3 heures |
| Création des manifests RBAC | 3-4 heures |
| Création du script de validation | 2-3 heures |
| Rédaction de l'ADR | 1-2 heures |
| Tests et ajustements | 1-2 heures |
| **Total** | **9-14 heures** (2-3 jours ouvrés) |

---

## 🎯 Questions de réflexion

Pour valider votre compréhension, posez-vous ces questions :

1. Quelle est la différence fondamentale entre un Role et un ClusterRole ? Quand utiliser l'un plutôt que l'autre ?
2. Pourquoi est-il déconseillé d'utiliser des ClusterRoleBinding pour des utilisateurs humains ?
3. Comment le principe du moindre privilège s'applique-t-il concrètement dans votre conception ?
4. Quels sont les risques si un ServiceAccount CI/CD a trop de permissions ?
5. Comment vérifier rapidement si un utilisateur a le droit d'effectuer une action spécifique ?

---

*Cette mission est conçue pour être réalisée de manière autonome. Si vous êtes bloqué, relisez les ressources indiquées et reformulez le problème en vos propres termes avant de demander de l'aide.*