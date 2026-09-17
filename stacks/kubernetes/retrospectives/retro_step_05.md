```markdown
# Rétrospective - Étape 5 : ResourceQuotas et LimitRanges

Cette rétrospective couvre l'étape 5 du parcours Kubernetes Entreprise, axée sur la mise en place des ResourceQuotas et LimitRanges pour une meilleure gouvernance des ressources et la protection du cluster.

---

## 1. Ce qui s'est bien passé

*   **Validation technique réussie :** La validation SRE a été un succès complet (7/7 tests passés), confirmant l'application correcte et fonctionnelle des quotas et limites dans tous les namespaces ciblés. Cela démontre une bonne compréhension et une implémentation robuste.
*   **Protection du cluster renforcée :** Le cluster est désormais protégé contre les consommations excessives de ressources, réduisant significativement le risque de déni de service et garantissant une meilleure stabilité et prédictibilité des performances pour toutes les applications hébergées.
*   **Standardisation et automatisation :** L'intégration des ResourceQuotas et LimitRanges via Kustomize dans la structure `stacks/kubernetes/infra/base` assure une gestion centralisée, versionnée et automatisée de ces politiques, facilitant leur déploiement et leur maintenance.

## 2. Ce qui a été difficile

*   **Définition des valeurs initiales :** Établir les valeurs initiales des quotas et limites par environnement (dev, staging, prod, tools) a nécessité des discussions approfondies pour trouver le juste équilibre entre une protection stricte et la flexibilité nécessaire aux applications. Il y a toujours un risque de sur-contraindre ou de sous-contraindre.
*   **Anticipation de l'impact applicatif :** Anticiper l'impact réel de ces restrictions sur les futurs déploiements applicatifs, notamment pour les équipes de développement qui n'ont pas encore l'habitude de spécifier précisément leurs `requests` et `limits`, a été un défi.

## 3. Leçons apprises

*   **Gouvernance proactive essentielle :** L'importance d'une gouvernance proactive des ressources est primordiale dès les premières étapes du parcours Kubernetes pour prévenir les problèmes de performance et de stabilité à grande échelle, plutôt que de réagir aux incidents.
*   **Ajustement itératif des politiques :** Les quotas et limites ne sont pas statiques. Ils devront être ajustés de manière itérative en fonction des métriques d'utilisation réelles (en lien avec l'observabilité de l'étape 4) et des besoins évolutifs des applications.
*   **Nécessité de la communication et de l'accompagnement :** Une communication claire et continue avec les équipes de développement est indispensable pour les sensibiliser à ces nouvelles contraintes et les accompagner dans la définition optimale de leurs `requests` et `limits` pour leurs applications.

## 4. Risque reporté

*   **Risque :** Des déploiements applicatifs futurs pourraient échouer ou rencontrer des problèmes de performance inattendus si les `requests` et `limits` définis par les équipes applicatives ne sont pas en adéquation avec les `ResourceQuotas` et `LimitRanges` mis en place.
*   **Mitigation esquissée :** Mettre en place un processus de revue des manifestes applicatifs avant déploiement pour valider les définitions de ressources. Renforcer la documentation interne sur les bonnes pratiques de définition des ressources. Utiliser les alertes configurées lors de l'étape 4 pour détecter rapidement les violations de quotas ou les situations de contention.

## 5. Conseil pour la prochaine étape (Étape 6 : Stratégies avancées : Blue/Green et Canary)

Pour l'étape 6, qui introduit des stratégies de déploiement avancées comme Blue/Green et Canary, il sera crucial de bien comprendre leur impact sur la consommation de ressources. Ces stratégies impliquent souvent le déploiement temporaire de versions multiples d'une application, ce qui peut doubler ou tripler la consommation de pods et de ressources. Il faudra s'assurer que les quotas actuels ne bloquent pas ces mécanismes et, si nécessaire, prévoir des ajustements temporaires ou des quotas plus souples pour les namespaces de déploiement.

## 6. Décisions clés

*   **Adoption de ResourceQuotas et LimitRanges par namespace :** La décision a été prise d'implémenter des `ResourceQuota` et `LimitRange` différenciés pour chaque namespace (`dev`, `staging`, `prod`, `tools`), offrant une protection granulaire et adaptée aux spécificités de chaque environnement.
*   **Intégration via Kustomize :** Les configurations de quotas et limites ont été intégrées à la base Kustomize existante (`stacks/kubernetes/infra/base/`), assurant une gestion cohérente et automatisée de l'infrastructure.
*   **Définition de valeurs initiales conservatrices :** Des valeurs initiales volontairement conservatrices ont été définies pour les quotas et limites afin de garantir la stabilité du cluster dès le départ, avec l'engagement de les ajuster au fur et à mesure de l'acquisition de données d'utilisation réelles.
```