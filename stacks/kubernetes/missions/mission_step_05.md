Bonjour,

Nous abordons une étape cruciale pour la stabilité et la gestion des coûts de notre infrastructure Kubernetes : la protection contre les consommations excessives de ressources. Cette mission vise à implémenter des mécanismes de gouvernance pour garantir une utilisation équitable et prévisible des ressources du cluster.

---

### Étape 5 : ResourceQuotas et LimitRanges

**Objectif :** Protéger le cluster des consommations excessives avec des quotas par namespace et des limites par conteneur, assurant ainsi la stabilité et la prévisibilité des performances de nos applications.

**Risque métier associé :** Sans ResourceQuotas et LimitRanges, une application mal configurée ou défaillante pourrait consommer l'intégralité des ressources d'un nœud, voire du cluster, entraînant un déni de service ou une dégradation significative des performances pour toutes les autres applications hébergées. Cela peut impacter directement la disponibilité de nos services critiques et la satisfaction de nos utilisateurs.

**Estimation de temps :** 1 jour

---

#### 1. À lire

Pour cette étape, il est essentiel de bien comprendre les concepts et les implications de la gestion des ressources dans Kubernetes.

*   **Documentation officielle Kubernetes sur les ResourceQuotas :**
    *   Comprendre leur rôle dans la limitation de la consommation globale d'un namespace.
    *   Identifier les types de ressources qui peuvent être limitées (CPU, mémoire, nombre de pods, de services, etc.).
    *   Analyser comment les quotas sont appliqués et les comportements attendus en cas de dépassement.
*   **Documentation officielle Kubernetes sur les LimitRanges :**
    *   Saisir leur fonction pour définir des requêtes et limites par défaut pour les conteneurs au sein d'un namespace.
    *   Appréhender l'importance de définir des requêtes (requests) et des limites (limits) pour le CPU et la mémoire.
    *   Comprendre l'impact de l'absence de LimitRanges sur le comportement des pods et la planification des ressources.
*   **Bonnes pratiques en entreprise pour la gestion des ressources :**
    *   Rechercher des exemples de stratégies de dimensionnement des ressources pour différents environnements (dev, staging, prod).
    *   Considérer l'équilibre entre l'optimisation des coûts et la garantie de performance.

---

#### 2. À créer

Vous devrez produire les artefacts suivants, en vous basant sur les principes d'isolation par namespace déjà établis.

1.  **Manifests Kubernetes pour les ResourceQuotas :**
    *   `kubernetes/namespaces/dev/resourcequota_dev.yaml`
    *   `kubernetes/namespaces/staging/resourcequota_staging.yaml`
    *   `kubernetes/namespaces/prod/resourcequota_prod.yaml`
    *   `kubernetes/namespaces/tools/resourcequota_tools.yaml`
    *   **Exigences :**
        *   Chaque fichier doit définir un `ResourceQuota` pour le namespace correspondant.
        *   Les quotas doivent inclure des limites pour le CPU (`requests.cpu`, `limits.cpu`) et la mémoire (`requests.memory`, `limits.memory`).
        *   Des quotas sur le nombre de pods (`pods`), de services (`services`) et de déploiements (`deployments`) doivent également être définis.
        *   Les valeurs des quotas doivent être différenciées par environnement : `dev` aura les quotas les plus bas, `staging` des quotas intermédiaires, et `prod` les quotas les plus élevés pour assurer la disponibilité des applications critiques. Le namespace `tools` doit avoir des quotas adaptés à ses services d'infrastructure (Prometheus, Grafana).
    *   **Critères d'acceptation :**
        *   Les manifests sont valides et peuvent être appliqués sans erreur.
        *   Les quotas sont cohérents avec les besoins typiques de chaque environnement.
        *   Les quotas sont suffisamment restrictifs pour éviter les abus, mais assez permissifs pour permettre le fonctionnement normal des applications.

2.  **Manifests Kubernetes pour les LimitRanges :**
    *   `kubernetes/namespaces/dev/limitrange_dev.yaml`
    *   `kubernetes/namespaces/staging/limitrange_staging.yaml`
    *   `kubernetes/namespaces/prod/limitrange_prod.yaml`
    *   `kubernetes/namespaces/tools/limitrange_tools.yaml`
    *   **Exigences :**
        *   Chaque fichier doit définir un `LimitRange` pour le namespace correspondant.
        *   Les `LimitRanges` doivent spécifier des `defaultRequest` et `default` (limite) pour le CPU et la mémoire des conteneurs.
        *   Les valeurs doivent être adaptées à chaque environnement, avec des limites plus généreuses en `prod` et plus contenues en `dev`.
    *   **Critères d'acceptation :**
        *   Les manifests sont valides et peuvent être appliqués sans erreur.
        *   Les valeurs par défaut sont raisonnables pour les applications typiques de chaque environnement.
        *   Les `LimitRanges` garantissent que chaque conteneur aura des requêtes et limites définies, même si elles ne sont pas explicitement spécifiées dans le déploiement.

3.  **ADR (Architecture Decision Record) final :**
    *   `infra/adrs/adr_step_05_final.md`
    *   **Exigences :**
        *   Documenter la décision d'implémenter des `ResourceQuotas` et `LimitRanges`.
        *   Justifier les choix de valeurs spécifiques pour chaque environnement (`dev`, `staging`, `prod`, `tools`) en termes de CPU, mémoire, et nombre d'objets.
        *   Expliquer les bénéfices attendus (stabilité, prévisibilité, gestion des coûts) et comment ces mesures atténuent le risque métier identifié.
        *   Mentionner les alternatives considérées (par exemple, ne pas utiliser de quotas, utiliser des quotas plus granulaires, etc.) et pourquoi elles ont été rejetées.
    *   **Critères d'acceptation :**
        *   L'ADR est clair, concis et complet.
        *   Les justifications sont solides et basées sur les principes de l'ingénierie logicielle et DevOps.
        *   Le document est conforme au format ADR standard de l'entreprise.

4.  **Script de validation :**
    *   `tests/step_05_validation.sh`
    *   **Exigences :**
        *   Le script doit vérifier la présence et la configuration correcte des `ResourceQuotas` et `LimitRanges` dans les namespaces `dev`, `staging`, `prod` et `tools`.
        *   Il doit valider que les valeurs définies (CPU, mémoire, nombre de pods/services/deployments) correspondent aux attentes pour chaque environnement.
        *   Le script doit être exécutable et retourner un statut clair (succès/échec).
    *   **Critères d'acceptation :**
        *   Le script s'exécute sans erreur.
        *   Il valide de manière fiable la conformité des ressources déployées.
        *   Le script est idempotent et peut être exécuté plusieurs fois.

---

#### 3. À livrer

Pour valider cette étape, veuillez soumettre une Pull Request contenant les éléments suivants :

*   Les manifests Kubernetes pour les `ResourceQuotas` et `LimitRanges` dans les répertoires spécifiés.
*   Le fichier `infra