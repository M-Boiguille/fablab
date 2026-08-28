# Ressources de lecture - Kubernetes Entreprise

## Etape 1 : Namespaces et isolation des environnements
- Kubernetes in Action, ch. Namespaces
- Documentation Kubernetes : Namespaces
- Patterns : un namespace par equipe et par environnement

## Etape 2 : RBAC et moindre privilège
- Kubernetes Security, ch. RBAC
- Documentation Kubernetes : Using RBAC Authorization
- Best practices : eviter ClusterRole sauf pour les operateurs cluster

## Etape 3 : Deployments basiques avec RollingUpdate
- Kubernetes in Action, ch. Deployments
- Documentation : Updating a Deployment, Rolling Update Strategy
- CKAD : Deployment et Rollout

## Etape 4 : Probes et observabilité applicative
- Kubernetes Patterns, ch. Health Probes
- Prometheus : premier pas avec kube-prometheus
- Grafana : dashboards Kubernetes

## Etape 5 : ResourceQuotas et LimitRanges
- Kubernetes in Action, ch. Limiting resources
- Documentation : ResourceQuotas, LimitRanges
- FinOps K8s : request/limit, overcommit

## Etape 6 : Stratégies avancées - Blue/Green et Canary
- Kubernetes Deployment Strategies
- Argo Rollouts : concepts et premiers pas
- Blue/Green vs Canary : trade-offs

## Etape 7 : GitOps avec ArgoCD
- GitOps and Kubernetes, ch. ArgoCD
- ArgoCD Documentation : Getting Started
- Structure de repo par environnement

## Etape 8 : Helm et Kustomize
- Learning Helm, ch. 1-5
- Kustomize : official documentation
- Comparaison Helm vs Kustomize

## Etape 9 : Sécurité réseau avec NetworkPolicy
- Kubernetes Security, ch. Network Security
- Calico NetworkPolicy tutorial
- Default-deny pattern

## Etape 10 : Pod Security et policies d'admission
- Pod Security Admission documentation
- Kyverno : policies examples
- OPA/Gatekeeper : fundamentals

## Etape 11 : Gestion des secrets
- Kubernetes Secrets documentation
- Sealed Secrets : getting started
- External Secrets Operator overview

## Etape 12 : Supply chain et sécurité des images
- Trivy : image scanning
- Cosign : signing containers
- Kyverno image verification

## Etape 13 : Sauvegarde et reprise après sinistre
- Velero documentation
- etcd backup and restore
- Plan de reprise DRP : RPO/RTO

## Etape 14 : Audit, traçabilité et conformité
- Kubernetes Audit documentation
- OIDC authentication
- SIEM basics for Kubernetes

## Etape 15 : Tests de charge et chaos engineering
- k6 documentation
- Locust quickstart
- Chaos Mesh : pod-kill experiment

## Etape 16 : Runbooks, ADR et gestion du cycle de vie
- Google SRE Book : runbooks
- ADR (Architecture Decision Records)
- Kubernetes version skew policy
