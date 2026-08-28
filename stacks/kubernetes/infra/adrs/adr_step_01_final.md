# ADR-001 : Structure des namespaces pour isolation des environnements

## Statut
Accepté

## Date
2026-08-28

## Contexte
Le cluster Kubernetes mutualisé doit héberger plusieurs environnements (dev, staging, prod) et des outils transverses. Sans isolation claire, les risques sont :
- Interférence entre environnements (un déploiement dev impacte la prod)
- Difficulté de gestion des quotas et des coûts
- Risque de sécurité (accès croisés non maîtrisés)

## Décision
Nous adoptons une structure de namespaces par environnement :
- `dev` : développement
- `staging` : pré-production
- `prod` : production
- `tools` : outils transverses (monitoring, CI/CD, etc.)

Chaque namespace porte des labels standardisés (`environment`, `team`, `managed-by`) pour faciliter l'automatisation et la gouvernance.

## Conséquences
- **Positives** : isolation logique claire, base pour RBAC et quotas, simplicité de gestion
- **Négatives** : nécessite une discipline stricte de nommage, risque de prolifération si non gouverné
- **Risques** : un namespace mal configuré peut exposer des ressources sensibles

## Alternatives considérées
1. **Un seul namespace** : rejeté — aucun isolation, risques majeurs
2. **Namespaces par équipe uniquement** : rejeté — pas d'isolation entre environnements
3. **Clusters séparés** : rejeté — coût et complexité opérationnelle trop élevés
