# ADR - Étape 02 : RBAC et moindre privilège

## Contexte
https://github.com/M-Boiguille/fablab/pull/3#issue-5282723309

## Décision
Utiliser un ClusterRole (définition des permissions) associé à deux RoleBindings (un dans dev, un dans staging) pour le CI/CD et les Devs. Cela permet de mutualiser la définition des règles (DRY - Don't Repeat Yourself) tout en restreignant efficacement leur portée aux seuls namespaces ciblés, empêchant tout accès à prod et tool

Pour l'équipe SRE, nous utilisons une double approche :

- Un RoleBinding dans le namespace prod lié à un Role (ou ClusterRole) pour les ressources namespace-scoped (pods, services, events, resourcequotas).
- Un ClusterRoleBinding (sans namespace) lié à un ClusterRole pour les ressources cluster-scoped (nodes, persistentvolumes).

Cette séparation est imposée par Kubernetes : un RoleBinding ne peut pas donner de droits sur des ressources qui n'appartiennent à aucun namespace. Le ClusterRoleBinding est donc obligatoire pour les permissions globales.

## Alternatives considérées
Alternative A (ma décision) : Gestion centralisée et évolutive. Une seule règle à modifier si les permissions évoluent.

Alternative B : Créer deux Roles distincts (un dans dev, un dans staging) et deux RoleBindings. Cela renforce la sécurité (moindre privilège absolu) car une erreur dans le Role dev n'impactera jamais le staging, mais cela double la maintenance et le risque d'oubli de mise à jour.

## Trade-offs
Le choix du ClusterRole + RoleBindings simplifie la maintenance au prix d'un risque : toute modification de la règle impacte simultanément dev et staging. Ce trade-off est acceptable en environnement d'homologation/staging partagé.
Cette architecture implique deux objets distincts pour le SRE (un RoleBinding et un ClusterRoleBinding), ce qui alourdit légèrement la gestion mais respecte strictement le modèle de sécurité de Kubernetes et évite une sur-permission en liant des droits globaux à un namespace.

## Références
###: Livres et documentation :

Kubernetes (Dunod): chapitre RBAC
Documentation Kubernetes : "Using RBAC Authorization"
Modules KodeKloud - CKA : Role-Based Access Control (RBAC)

