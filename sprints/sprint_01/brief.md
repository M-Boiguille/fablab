# Brief Sprint 1 - Fondations Kubernetes

## Contexte métier

L'entreprise souhaite industrialiser le déploiement de ses applications sur Kubernetes. Le profil actuel montre une maîtrise solide des objets Kubernetes de base (Pods, Deployments, Services, ConfigMaps, Secrets) mais aucune expérience en infrastructure as code, scripting, ou gestion réseau avancée. Ce premier sprint pose les fondations d'une plateforme fiable et sécurisée.

## Objectif du sprint

**Renforcer la maîtrise des fondamentaux Kubernetes pour garantir des déploiements fiables et observables.**

Le sprint vise à consolider les acquis existants (niveau 0.83) vers une maîtrise opérationnelle complète, en introduisant les concepts de gestion des ressources, d'observabilité et de stratégies de déploiement.

## Livrables attendus

### 1. Namespaces et isolation (Étape 1)
- Créer une structure de namespaces par environnement (dev, staging, prod)
- Documenter la stratégie d'isolation

### 2. RBAC et moindre privilège (Étape 2)
- Implémenter des Roles et RoleBindings par namespace
- Créer des ServiceAccounts dédiés par application
- **Critère de sortie :** aucun ClusterRoleBinding non justifié

### 3. Deployments avec RollingUpdate (Étape 3)
- Déployer 3 applications avec stratégie RollingUpdate
- Configurer les stratégies de mise à jour (maxUnavailable, maxSurge)
- **Critère de sortie :** rollback testé et documenté

### 4. Probes et observabilité (Étape 4)
- Ajouter readinessProbe, livenessProbe et startupProbe sur tous les workloads
- Déployer Prometheus et Grafana (kube-prometheus-stack)
- **Critère de sortie :** dashboards opérationnels, alertes de base configurées

### 5. ResourceQuotas et LimitRanges (Étape 5)
- Définir des quotas par namespace
- Configurer des limites par défaut pour les conteneurs
- **Critère de sortie :** aucun pod sans request/limit

### 6. Stratégies avancées (Étape 6)
- Implémenter une stratégie Blue/Green sur une application
- Implémenter une stratégie Canary sur une autre
- Documenter les trade-offs et le processus de bascule

## Définition of Done

- [ ] Tous les manifests sont versionnés dans un repo Git
- [ ] Documentation technique rédigée (architecture, procédures)
- [ ] Tests de validation effectués (rollback, bascule, montée en charge)
- [ ] Revue de code et validation par un pair
- [ ] Démonstration fonctionnelle réalisée

## Ressources

- **Livres :** Kubernetes in Action (ch. Namespaces, Deployments, Limiting resources), Kubernetes Patterns (ch. Health Probes)
- **Modules KodeKloud :** CKA/CKAD - Namespaces, RBAC, Deployments, Probes, Resource Quotas, Deployment Strategies
- **Documentation officielle :** Kubernetes.io (Namespaces, RBAC, Deployments, ResourceQuotas)