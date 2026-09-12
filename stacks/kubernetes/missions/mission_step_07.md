Bonjour,

Nous abordons une étape cruciale pour la robustesse et l'optimisation de notre plateforme Kubernetes : le **Scheduling avancé**. L'objectif est de maîtriser la manière dont Kubernetes place les pods sur les nœuds, en introduisant des mécanismes de contrôle plus fins que le simple scheduler par défaut. Cela nous permettra de répondre à des besoins spécifiques comme la collecte de logs sur tous les nœuds, l'exécution de composants critiques avec une haute priorité, ou le placement de charges de travail sur des nœuds dédiés.

---

### **Étape 7 : Scheduling avancé**

**Objectif :** Maîtriser les mécanismes de scheduling avancés de Kubernetes pour optimiser le placement des pods et la gestion des ressources du cluster.

---

#### **A lire**

Pour cette étape, il est essentiel de bien comprendre les concepts fondamentaux du scheduling. Je vous invite à consulter la documentation officielle de Kubernetes sur les sujets suivants :

*   **Taints et Tolerations :** Comment marquer des nœuds pour repousser certains pods et comment les pods peuvent tolérer ces marques pour être planifiés.
*   **Node Selectors :** La méthode la plus simple pour contraindre un pod à s'exécuter sur un nœud avec un label spécifique.
*   **Node Affinity/Anti-affinity :** Des règles plus expressives pour attirer ou repousser des pods vers/depuis des nœuds en fonction de leurs labels, avec des options "required" et "preferred".
*   **DaemonSets :** Pour garantir qu'un pod s'exécute sur *tous* les nœuds (ou un sous-ensemble) du cluster.
*   **Static Pods :** Des pods gérés directement par le kubelet sur un nœud spécifique, sans passer par l'API Server.
*   **PriorityClass et Preemption :** Comment définir des niveaux de priorité pour les pods et permettre aux pods de haute priorité de "préempter" (expulser) des pods de basse priorité en cas de manque de ressources.

**Rappel important :** Comme mentionné dans la roadmap, n'oubliez pas de revoir les concepts de **labels/selectors** (étape 3) et de **quotas CPU** (étape 5), car ils sont des prérequis essentiels pour comprendre et appliquer le scheduling avancé.

---

#### **A créer**

Votre mission consiste à implémenter les éléments suivants dans notre environnement Fablab :

1.  **Un DaemonSet de collecte de logs :**
    *   **Exigences :** Créez un DaemonSet qui déploie un pod sur chaque nœud de votre cluster. Ce pod doit simuler un agent de collecte de logs en montant un volume `hostPath` pointant vers un répertoire de logs système (par exemple, `/var/log`). Le conteneur peut simplement afficher en continu le contenu d'un fichier de log ou un message indicatif.
    *   **Critères d'acceptation :**
        *   Un manifeste de type `DaemonSet` est créé.
        *   Le DaemonSet déploie un pod sur chaque nœud éligible du cluster.
        *   Chaque pod du DaemonSet est en état `Running`.
        *   Les pods montent un `hostPath` pour accéder aux logs du nœud.

2.  **Un Static Pod Nginx :**
    *   **Exigences :** Déployez une instance Nginx en tant que Static Pod sur un nœud de votre choix (par exemple, le nœud maître si vous utilisez un cluster à un seul nœud, ou un nœud worker désigné). Ce déploiement ne doit pas passer par l'API Kubernetes.
    *   **Critères d'acceptation :**
        *   Un fichier de manifeste de pod est créé et placé dans le répertoire de configuration des Static Pods du kubelet sur le nœud cible.
        *   Le pod Nginx est visible via `kubectl get pods` et est géré par le kubelet local.
        *   Le pod Nginx est en état `Running`.

3.  **Une PriorityClass pour l'application Fablab :**
    *   **Exigences :** Définissez une `PriorityClass` avec une priorité élevée. Appliquez cette `PriorityClass` au déploiement Nginx existant de notre application Fablab (celui de l'étape 3).
    *   **Critères d'acceptation :**
        *   Un manifeste de type `PriorityClass` est créé avec une valeur numérique significative.
        *   Le déploiement Nginx de l'application Fablab est mis à jour pour référencer cette `PriorityClass`.
        *   Les pods Nginx de l'application Fablab affichent la `PriorityClass` configurée.

4.  **Placement de pods sur des nœuds dédiés via Affinity/Tolerations :**
    *   **Exigences :** Simulez un scénario où une instance spécifique de Nginx (distincte de l'application Fablab principale) doit s'exécuter sur un nœud "premium" ou "isolé".
        *   Marquez un nœud de votre cluster avec un label spécifique (par exemple, `node-role.kubernetes.io/premium: "true"`).
        *   Créez un nouveau déploiement Nginx (avec un seul replica) qui utilise `nodeAffinity` (plutôt que `nodeSelector` pour explorer une option plus flexible) pour s'assurer qu'il est planifié *uniquement* sur ce nœud labellisé.
        *   Pour aller plus loin, ajoutez un `taint` sur ce même nœud (par exemple, `dedicated=premium:NoSchedule`) et assurez-vous que le déploiement Nginx dédié inclut la `toleration` correspondante pour pouvoir y être planifié.
    *   **Critères d'acceptation :**
        *   Un nœud du cluster est labellisé avec le label choisi.
        *   Le même nœud est "tainté" avec le taint spécifié.
        *   Un nouveau manifeste de déploiement Nginx est créé.
        *   Ce déploiement utilise `nodeAffinity` pour cibler le nœud labellisé.
        *   Ce déploiement inclut la `toleration` nécessaire pour le taint du nœud.
        *   Le pod Nginx de ce déploiement est planifié et en état `Running` *uniquement* sur le nœud désigné.

5.  **ADR (Architecture Decision Record) pour le Scheduling avancé :**
    *   **Nom du fichier :** `infra/adrs/adr_step_07_final.md`
    *   **Exigences :** Rédigez un ADR documentant les décisions prises concernant l'implémentation du scheduling avancé. Justifiez vos choix pour l'utilisation de `DaemonSet`, `Static Pods`, `PriorityClass`, et la combinaison de `NodeAffinity` et `Tolerations`. Expliquez pourquoi ces outils sont pertinents pour les scénarios décrits.
    *   **Critères d'acceptation :**
        *   L'ADR est rédigé dans le format standard (contexte, décision, conséquences).
        *   Il justifie clairement les choix techniques et les compromis.
        *   Il est concis et facile à comprendre.

---

#### **A livrer**

Pour valider cette étape, veuillez soumettre les éléments suivants :

1.  **Les manifests YAML** de tous les objets Kubernetes créés ou modifiés (DaemonSet, PriorityClass, déploiements Nginx, etc.).
2.  Le fichier de configuration du **Static Pod**.
3.  Le script de validation : `tests/step_07_validation.sh`
    *   Ce script doit vérifier la bonne application de tous les concepts ci-dessus. Il devra notamment :
        *   Vérifier que le DaemonSet est déployé et que ses pods sont `Running` sur les nœuds attendus.
        *   Vérifier que le Static Pod Nginx est `Running` sur le nœud cible.
        *   Vérifier que la `PriorityClass` existe et est appliquée au déploiement Nginx de l'application Fablab.
        *   Vérifier que le nœud "premium" est correctement labellisé et "tainté".
        *   Vérifier que le déploiement Nginx dédié est planifié *uniquement* sur le nœud "premium" et que son pod est `Running`.
        *   Utilisez des commandes `kubectl get`, `kubectl describe`, `kubectl logs` avec des filtres appropriés pour ces vérifications.
4.  Le fichier de résultat : `tests/step_07_result.txt`
    *   Ce fichier contiendra la sortie de l'exécution de votre script de validation.
5.  L'ADR final : `infra/adrs/adr_step_07_final.md`

**Commande de validation suggérée :**
```bash
./tests/step_07_validation.sh > tests/step_07_result.txt
```

**Marqueur de succès :** Le fichier `tests/step_07_result.txt` doit contenir la mention "PASS" à la fin, indiquant que toutes les vérifications ont réussi.

---

**Risque métier réaliste :**
Un mauvais usage des mécanismes de scheduling avancés (par exemple, des taints trop restrictifs sans tolérations adéquates, ou des affinités mal configurées) peut entraîner des pods qui restent en état `Pending` indéfiniment, rendant des applications indisponibles ou sous-utilisant les ressources du cluster. Cela peut impacter directement la disponibilité de nos services et générer des coûts inutiles.

**Estimation de temps :** 4 à 6 heures.

Bon courage pour cette étape enrichissante !