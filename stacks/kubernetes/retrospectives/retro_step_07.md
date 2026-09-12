```markdown
# Rétrospective - Étape 7 : Scheduling avancé

**Date :** 2025-05-18
**Étape :** 7 - Scheduling avancé
**Contexte :** Parcours Kubernetes CKA - Projet Fablab
**Outil principal :** kubectl

---

## 1. Ce qui s'est bien passé

*   **Validation complète et réussie :** Tous les scénarios de scheduling avancé (DaemonSet, Static Pod, PriorityClass, Node Affinity/Tolerations) ont été validés avec succès sur le cluster K3s mono-nœud. Cela démontre une excellente compréhension des mécanismes par l'équipe.
*   **Préparation au multi-nœuds :** Les manifests créés sont déjà conçus pour être fonctionnels dans un environnement multi-nœuds, ce qui anticipe les évolutions futures du cluster Fablab et réduit la dette technique.
*   **Sécurité proactive :** L'intégration d'un `securityContext` durci pour le `DaemonSet` de collecte de logs, malgré l'utilisation de `hostPath` et l'exécution en `root`, est une excellente pratique qui montre une conscience des enjeux de sécurité dès les premières étapes.

## 2. Ce qui a été difficile

*   **Rigueur du mono-nœud :** La contrainte d'un cluster mono-nœud a exigé une grande précision dans la manipulation des taints et des affinités. Une erreur aurait pu bloquer la planification de tous les pods, nécessitant une attention particulière lors des tests.
*   **Gestion des objets temporaires :** Le déploiement et le retrait de composants temporaires (comme le Static Pod Nginx ou les taints/labels de nœud pour la démonstration d'affinité) ont demandé une gestion méticuleuse pour ne pas impacter durablement le cluster.

## 3. Leçons apprises

*   **Complémentarité des mécanismes :** Les Taints, Tolerations et Affinités sont des outils puissants et complémentaires. Leur combinaison est essentielle pour un placement précis et robuste des pods sur des nœuds spécifiques.
*   **Importance de `preemptionPolicy` :** Sur des clusters à ressources limitées ou mono-nœuds, la `preemptionPolicy: Never` dans une `PriorityClass` est cruciale pour éviter l'éviction inattendue de pods existants, y compris des composants d'infrastructure.
*   **Sécurisation des privilèges :** L'utilisation de `securityContext` est impérative pour mitiger les risques liés aux privilèges élevés (ex: `hostPath`, exécution en `root`), même lorsque ces privilèges sont techniquement nécessaires.

## 4. Risque reporté

*   **Risque :** L'utilisation de `hostPath` et l'exécution en `root` pour le `DaemonSet` de collecte de logs, même avec un `securityContext` durci, représente un privilège élevé qui expose potentiellement le système de fichiers hôte.
*   **Mitigation esquissée :** Tout besoin d'élargir le périmètre de ce `DaemonSet` ou d'assouplir son `securityContext` devra faire l'objet d'une revue de sécurité approfondie et d'une justification explicite, documentée via un nouvel ADR si nécessaire.

## 5. Conseil pour la prochaine étape

*   Pour l'étape 8 (ConfigMaps, Secrets et patterns multi-conteneurs), maintenir la même rigueur dans la gestion des configurations et des secrets. La sensibilité des données manipulées exigera une attention particulière aux bonnes pratiques de sécurité et de gestion du cycle de vie.

## 6. Décisions clés

*   **Déploiement du DaemonSet de logs :** Utilisation d'un `DaemonSet` pour la collecte de logs, montant `/var/log/pods/` via `hostPath`, avec un `securityContext` durci pour limiter les risques.
*   **Démonstration du Static Pod :** Déploiement temporaire d'un `Static Pod` Nginx pour illustrer la gestion directe par le kubelet, hors API Server.
*   **Définition de la PriorityClass :** Création d'une `PriorityClass` `nginx` avec une valeur de 1000 et `preemptionPolicy: Never` pour l'application Fablab, afin de garantir sa stabilité sans éviction agressive.
*   **Simulation de nœud dédié :** Mise en œuvre d'une `nodeAffinity` `requiredDuringSchedulingIgnoredDuringExecution` et d'une `toleration` correspondante pour simuler le placement de pods sur un nœud « premium » labellisé et teinté.
```