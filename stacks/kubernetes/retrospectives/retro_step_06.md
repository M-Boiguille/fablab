```markdown
# Rétrospective - Étape 6 : Stratégies avancées (Blue/Green et Canary)

**Date :** 2023-10-27
**Étape :** 6 - Stratégies avancées : Blue/Green et Canary
**Outil principal :** kubectl
**Contexte :** Validation de l'implémentation des stratégies de déploiement Blue/Green en `staging` et Canary en `dev` pour l'application `nginx`, en respectant les `ResourceQuota` et `LimitRange` définis précédemment.

---

## Ce qui s'est bien passé

1.  **Validation réussie des stratégies :** Les tests ont confirmé le bon fonctionnement des déploiements Blue/Green et Canary, avec une bascule de trafic et une progression par paliers conformes aux attentes. Les scripts de validation ont été efficaces pour démontrer la continuité de service et la répartition du trafic.
2.  **Choix stratégique pertinent :** La décision d'appliquer Blue/Green en `staging` (pour un rollback rapide) et Canary en `dev` (pour l'expérimentation progressive) s'est avérée judicieuse et a été bien justifiée par les besoins spécifiques de chaque environnement.
3.  **Intégration avec les quotas de ressources :** L'ajustement des `ResourceQuota` et `LimitRange` pour accommoder les deux versions de l'application (Blue/Green ou Stable/Canary) a été réalisé avec succès, démontrant une bonne compréhension des contraintes de ressources.

## Ce qui a été difficile

1.  **Ajustement des quotas et limites :** La nécessité d'ajuster les `requests`/`limits` et les quotas de `Deployment` dans les namespaces `dev` et `staging` a demandé une attention particulière pour permettre la coexistence des deux versions de l'application. Cela a mis en lumière la complexité de gérer les ressources lors de l'introduction de nouvelles stratégies de déploiement.
2.  **Observation manuelle du Canary :** Bien que fonctionnel, le déploiement Canary a requis une observation manuelle des pourcentages de trafic. L'absence d'automatisation pour l'analyse des métriques et la décision de progression ou de rollback représente une limitation pour une utilisation en production.

## Leçons apprises

1.  **L'importance de la bonne stratégie au bon endroit :** Chaque stratégie de déploiement (RollingUpdate, Blue/Green, Canary) a ses avantages et inconvénients. Choisir la bonne stratégie en fonction des objectifs de l'environnement (rapidité de rollback, observation progressive, etc.) est crucial.
2.  **Nécessité d'une identification claire des versions :** L'utilisation d'un endpoint `/version` et de labels distincts (`track: blue/green` ou `track: stable/canary`) est fondamentale pour valider et observer le comportement des différentes versions en production.
3.  **Anticipation des besoins en ressources :** Les stratégies avancées comme Blue/Green peuvent doubler temporairement la consommation de ressources. Il est essentiel d'anticiper ces pics et d'adapter les `ResourceQuota` en conséquence.

## Risque reporté

*   **Risque :** Dérive de configuration entre les versions Blue et Green. Les deux `Deployment` doivent rester identiques (hors image et label `track`), mais toute modification manuelle sur l'un sans l'autre pourrait entraîner des incohérences.
*   **Mitigation esquissée :** La factorisation des manifests via Kustomize (prévue à l'étape 15) est essentielle pour réduire ce risque. Elle permettra de définir une base commune et d'appliquer des surcouches minimales pour les différences (image, label), garantissant ainsi une meilleure cohérence.

## Conseil pour la prochaine étape

*   **Pour l'étape 7 (Scheduling avancé) :** Garder à l'esprit que la gestion de multiples `Deployment` (comme avec Blue/Green ou Canary) peut avoir des implications sur le placement des pods. Une bonne compréhension du `Scheduling avancé` sera utile pour optimiser l'utilisation des nœuds et la résilience, surtout si les ressources sont limitées.

## Décisions clés

*   **Répartition des stratégies :** Blue/Green adopté pour l'environnement `staging`, Canary pour l'environnement `dev`.
*   **Mécanisme Blue/Green :** Implémenté via la modification du sélecteur de `Service` (`spec.selector.track`).
*   **Mécanisme Canary :** Implémenté via le contrôle du nombre de réplicas pour chaque `Deployment` (stable et canary).
*   **Identification des versions :** Utilisation d'un endpoint `/version` et de labels `track` pour distinguer les versions.
*   **Ajustement des quotas :** Les `ResourceQuota` et `LimitRange` ont été ajustés pour permettre la coexistence des deux versions de l'application dans les environnements `dev` et `staging`.
```