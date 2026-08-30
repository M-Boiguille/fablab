# Brief Sprint 1 - Fondations Kubernetes

## Contexte métier

L'entreprise souhaite moderniser son infrastructure en adoptant Kubernetes comme plateforme d'orchestration. Le niveau actuel de l'équipe est débutant (niveau global 0.2/1.0) avec une exposition limitée aux concepts de base (Pods, Deployments, Services, ConfigMaps, Secrets). Ce premier sprint vise à établir des fondations solides et sécurisées avant de déployer des applications de production.

## Objectif du sprint

**Établir un environnement Kubernetes multi-équipes sécurisé et observable** permettant de déployer des applications avec des stratégies de mise à jour fiables et des limites de ressources contrôlées.

### Objectifs d'apprentissage
- Maîtriser les Namespaces pour l'isolation des environnements
- Comprendre et implémenter le RBAC avec le principe du moindre privilège
- Configurer des Deployments avec stratégie RollingUpdate
- Implémenter des Probes de santé et l'observabilité de base
- Appliquer des ResourceQuotas et LimitRanges

## Livrables attendus

### 1. Infrastructure de base
- [ ] **Namespaces** : Création de namespaces par environnement (dev, staging, prod) et par équipe
- [ ] **RBAC** : Configuration de Roles, RoleBindings, ClusterRoles et ClusterRoleBindings avec moindre privilège
- [ ] **ServiceAccounts** : Création et configuration des ServiceAccounts pour les workloads

### 2. Déploiement applicatif
- [ ] **Deployments** : Déploiement d'une application de démonstration avec stratégie RollingUpdate (maxSurge: 25%, maxUnavailable: 25%)
- [ ] **Probes** : Configuration des livenessProbe, readinessProbe et startupProbe
- [ ] **Services** : Exposition de l'application via Services (ClusterIP, NodePort)

### 3. Gouvernance des ressources
- [ ] **ResourceQuotas** : Définition des quotas par namespace (CPU, mémoire, nombre de pods)
- [ ] **LimitRanges** : Configuration des limites par défaut et des plages autorisées pour les conteneurs

### 4. Observabilité
- [ ] **Monitoring** : Installation de Prometheus et Grafana (kube-prometheus-stack)
- [ ] **Dashboards** : Création d'un dashboard Grafana de base pour les métriques Kubernetes

### 5. Documentation
- [ ] **Runbook** : Documentation des procédures de déploiement, de mise à jour et de rollback
- [ ] **ADR** : Décision d'architecture sur le choix des stratégies de déploiement et l'isolation des environnements

## Critères d'acceptation

- [ ] Tous les objets Kubernetes sont déployés via des manifestes versionnés (Git)
- [ ] Les accès sont limités par rôle et par namespace (vérification avec `kubectl auth can-i`)
- [ ] Une application de démonstration est déployée avec RollingUpdate fonctionnel
- [ ] Les ResourceQuotas et LimitRanges sont actifs et testés (tentative de dépassement refusée)
- [ ] Prometheus collecte les métriques et Grafana affiche un dashboard fonctionnel
- [ ] Le runbook documente les procédures de base (déploiement, mise à jour, rollback)

## Ressources

- **Livres** : Kubernetes in Action (ch. Namespaces, Deployments, Limiting resources), Kubernetes Security (ch. RBAC)
- **Documentation officielle** : Namespaces, RBAC Authorization, Deployments, ResourceQuotas, LimitRanges
- **Modules KodeKloud** : CKA Namespaces, CKA RBAC, CKAD Deployments, CKAD Probes, CKA Resource Quotas
- **Patterns** : Health Probes, Rolling Update Strategy