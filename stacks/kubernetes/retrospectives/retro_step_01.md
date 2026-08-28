# Rétrospective - Étape 1 : Namespaces et isolation des environnements

**Date :** 2026-08-28  
**Étape validée :** 1/16  
**Outil :** kubectl (Kubernetes)

---

## 1. Ce qui s'est bien passé

- **Structure claire et validée par l'ADR-001** : La décision de créer 4 namespaces (`dev`, `staging`, `prod`, `tools`) a été formalisée dans un ADR accepté, ce qui donne une base solide et documentée pour la suite du parcours.
- **Validation automatisée complète** : Les 12 vérifications (existence, labels, absence de pods) sont toutes passées. La discipline de nommage et de labellisation est en place dès le départ.
- **Choix pragmatique de l'isolation logique** : L'option "clusters séparés" a été écartée pour des raisons de coût et de complexité, ce qui est une décision réaliste pour une entreprise.

## 2. Ce qui a été difficile

- **Discipline de nommage** : Maintenir une convention stricte sur les labels (`environment`, `team`, `managed-by`) demande de la rigueur. Sans gouvernance, le risque de prolifération de namespaces est réel.
- **Éviter le piège du "namespace unique"** : La tentation de tout mettre dans un seul namespace pour simplifier est forte, mais l'ADR a permis de trancher proprement.

## 3. Leçons apprises

- **Documenter les décisions tôt** : L'ADR-001 a clarifié le "pourquoi" de la structure. C'est un réflexe à garder pour chaque étape.
- **L'isolation logique est un prérequis** : Sans namespaces bien définis, les étapes suivantes (RBAC, quotas, NetworkPolicy) seraient impossibles à mettre en œuvre proprement.
- **L'automatisation de la validation est payante** : Les vérifications par script (kubectl) permettent de valider rapidement et de façon reproductible.

## 4. Risque reporté

**Risque :** Prolifération de namespaces non gouvernés à l'avenir (ex. : un namespace par équipe ou par projet sans validation).

**Mitigation esquissée :** Mettre en place un processus de revue pour toute création de namespace, avec un naming convention obligatoire et un label `managed-by` renseigné. À terme, un outil de policy (Kyverno ou OPA) pourra imposer ces règles automatiquement (étape 10 du parcours).

## 5. Conseil pour la prochaine étape

**Étape 2 : RBAC et moindre privilège** — Profitez de la structure de namespaces en place pour définir des rôles par environnement. Commencez par un mapping simple : développeurs sur `dev`, QA sur `staging`, SREs sur `prod` et `tools`. Testez chaque binding avec un utilisateur fictif pour valider les permissions avant de passer à l'échelle.

## 6. Décisions clés

| Décision | Justification |
|----------|---------------|
| 4 namespaces : `dev`, `staging`, `prod`, `tools` | Isolation logique par environnement + outils transverses |
| Labels standardisés (`environment`, `team`, `managed-by`) | Base pour l'automatisation et la gouvernance |
| Rejet de l'option "clusters séparés" | Coût et complexité opérationnelle trop élevés |
| Rejet de l'option "namespace unique" | Aucune isolation, risques majeurs |
| Validation automatisée via kubectl | Reproductibilité et rapidité de contrôle |

---

**Prochain rendez-vous :** Étape 2 - RBAC et moindre privilège.