Bonjour,

Voici la mission pour l'étape 8 de votre parcours Kubernetes. L'objectif est de renforcer votre compréhension et votre maîtrise des ConfigMaps, Secrets et des patterns de conteneurs avancés.

---

### Mission: Étape 8 - ConfigMaps, Secrets et patterns multi-conteneurs

**Objectif :** Maîtriser la gestion des configurations et des données sensibles via ConfigMaps et Secrets, et explorer les patterns de déploiement multi-conteneurs pour améliorer la robustesse et la modularité de nos applications.

**Contexte :** Notre application Fablab utilise déjà un ConfigMap basique pour son `index.html`. Nous devons aller plus loin en externalisant l'intégralité de sa configuration Nginx, sécuriser les communications avec TLS, et introduire un sidecar pour la gestion des logs, préparant ainsi le terrain pour des architectures plus complexes.

**Risque métier réaliste :** Une mauvaise gestion des Secrets ou des ConfigMaps peut entraîner des fuites de données sensibles (clés API, certificats) ou des pannes applicatives difficiles à diagnostiquer si les configurations sont mal chargées ou supprimées par erreur. Par exemple, un certificat TLS mal configuré ou expiré peut rendre l'application inaccessible via HTTPS, impactant directement l'expérience utilisateur et la confiance.

**Estimation de temps :** 4-6 heures

---

### A lire

Pour cette étape, concentrez-vous sur les concepts suivants :

*   **Kubernetes Documentation Officielle :**
    *   [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) : Approfondissez les options, notamment l'immutabilité.
    *   [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) : Types de Secrets (Opaque, TLS), comment les créer et les utiliser.
    *   [Patterns de conteneurs](https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/#container-patterns) : Concentrez-vous sur les `init containers` et les `sidecar containers`.
    *   [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/) : Comprendre leur rôle et comment les tokens sont gérés.
*   **Ressources complémentaires :**
    *   Revoir la documentation sur la configuration de Nginx pour servir du contenu HTTPS avec des certificats.
    *   Revoir l'utilisation des ConfigMaps pour Nginx (étape 3) et les probes (étape 4).

---

### A creer

Vous devrez produire les artefacts suivants, en les intégrant à votre structure de projet existante (notamment via Kustomize si pertinent) :

1.  **Manifeste de ConfigMap Nginx étendu**
    *   **Exigences :**
        *   Externaliser l'intégralité de la configuration Nginx (fichier `nginx.conf` complet) dans un ConfigMap. Ce ConfigMap doit inclure la configuration pour servir à la fois HTTP (sur le port 80) et HTTPS (sur le port 443).
        *   Le ConfigMap doit être configuré comme `immutable`.
        *   Le `index.html` de l'étape 3 doit toujours être servi.
    *   **Critères d'acceptation :**
        *   Le Pod Nginx démarre et utilise la configuration du nouveau ConfigMap.
        *   La configuration Nginx est complète et fonctionnelle pour les requêtes HTTP et HTTPS.
        *   Le ConfigMap est marqué comme `immutable`.

2.  **Manifeste de Secret TLS auto-signé**
    *   **Exigences :**
        *   Créer un Secret de type `kubernetes.io/tls` contenant un certificat et une clé privée auto-signés.
        *   Ce Secret doit être monté dans le Pod Nginx pour permettre la terminaison TLS.
    *   **Critères d'acceptation :**
        *   Le Secret est créé et contient les données attendues (certificat et clé).
        *   Le Pod Nginx monte correctement le Secret et utilise le certificat pour servir HTTPS.

3.  **Mise à jour du Deployment Nginx pour HTTPS et Sidecar**
    *   **Exigences :**
        *   Modifier le Deployment Nginx existant pour :
            *   Utiliser la configuration Nginx externalisée via le nouveau ConfigMap.
            *   Monter le Secret TLS pour la terminaison HTTPS.
            *   Ajouter un nouveau port `443` au conteneur Nginx.
            *   Ajouter un conteneur `sidecar` dédié à la rotation des logs Nginx. Ce sidecar doit partager un volume `emptyDir` avec le conteneur Nginx pour accéder aux logs.
            *   Le conteneur Nginx doit être configuré pour écrire ses logs (access.log et error.log) sur le volume partagé.
            *   Le conteneur sidecar doit utiliser une image légère (ex: `busybox` ou `alpine`) et exécuter une commande simple pour simuler la rotation des logs (ex: `logrotate` ou un script shell basique qui déplace/vide les fichiers périodiquement).
            *   Assurez-vous que les `securityContext` des conteneurs Nginx et sidecar sont durcis au maximum (e.g., `runAsNonRoot`, `readOnlyRootFilesystem`, `drop capabilities`).
    *   **Critères d'acceptation :**
        *   Le Pod Nginx démarre avec deux conteneurs : `nginx` et le `sidecar`.
        *   Les logs Nginx sont écrits sur le volume partagé et le sidecar y accède.
        *   Le sidecar exécute sa tâche de rotation de logs sans erreur.
        *   Les `securityContext` sont correctement appliqués aux deux conteneurs.
        *   L'application Fablab est accessible via HTTP et HTTPS.

4.  **Script de validation (`tests/step_08_validation.sh`)**
    *   **Exigences :**
        *   Un script shell qui vérifie la bonne implémentation des exigences ci-dessus.
        *   Il doit vérifier la présence et l'immutabilité du ConfigMap.
        *   Il doit vérifier la présence et le type du Secret TLS.
        *   Il doit vérifier que le Deployment Nginx a bien deux conteneurs (nginx et sidecar) et que les ports 80 et 443 sont exposés.
        *   Il doit vérifier que les `securityContext` sont appliqués.
        *   Il doit tenter d'accéder à l'application via HTTP et HTTPS pour valider la connectivité.
        *   Il doit inclure un test pour le scénario "break-it" : simuler la suppression du ConfigMap référencé et vérifier l'état des Pods.
    *   **Critères d'acceptation :**
        *   Le script s'exécute sans erreur et produit un résultat clair.
        *   Il valide tous les points clés de la mission.
        *   Il inclut le test "break-it" et sa capacité à diagnostiquer le problème.

5.  **Fichier de résultat (`tests/step_08_result.txt`)**
    *   **Exigences :**
        *   Contient la sortie de l'exécution du script de validation.
    *   **Critères d'acceptation :**
        *   Le fichier existe et contient les logs du script.

6.  **ADR (Architectural Decision Record) final (`infra/adrs/adr_step_08_final.md`)**
    *   **Exigences :**
        *   Documenter les décisions clés prises pour cette étape.
        *   Expliquer le choix de l'immutabilité pour le ConfigMap Nginx.
        *   Justifier l'utilisation d'un Secret TLS auto-signé pour le moment (et mentionner les prochaines étapes pour une gestion plus robuste des certificats).
        *   Décrire le pattern `sidecar` choisi pour la rotation des logs, ses avantages et inconvénients par rapport à d'autres approches (ex: `init container`, gestion des logs par l'application elle-même).
        *   Mentionner les `securityContext` appliqués et leur importance.
    *   **Critères d'acceptation :**
        *   L'ADR est clair, concis et couvre tous les points requis.
        *   Il reflète une compréhension approfondie des choix techniques.

---

### A livrer

Pour valider cette étape, soumettez une Pull Request contenant les éléments suivants :

1.  Tous les manifests Kubernetes (`.yaml`) nécessaires pour déployer les ConfigMaps, Secrets et le Deployment Nginx mis à jour avec le sidecar. Ces manifests doivent être intégrés à votre structure Kustomize existante.
2.  Le script de validation : `tests/step_08_validation.sh`.
3.  Le fichier de résultat de l'exécution du script : `tests/step_08_result.txt`.
4.  L'ADR final : `infra/adrs/adr_step_08_final.md`.

**Commandes de validation suggérées :**

*   Déployez vos modifications : `kubectl apply -k stacks/kubernetes/infra/base/` (ou le chemin Kustomize approprié).
*   Exécutez votre script de validation : `./tests/step_08_validation.sh | tee tests/step_08_result.txt`
*   Vérifiez l'état des Pods : `kubectl get pods -n fablab`
*   Décrivez un Pod Nginx pour vérifier les conteneurs, volumes et montages : `kubectl describe pod <nginx-pod-name> -n fablab`
*   Vérifiez les logs du sidecar : `kubectl logs <nginx-pod-name> -c <sidecar-container-name> -n fablab`
*   Testez l'accès HTTP : `curl -k http://<service-ip>:80`
*   Testez l'accès HTTPS : `curl -k https://<service-ip>:443` (le `-k` est nécessaire pour les certificats auto-signés).

**Marqueurs de réussite :**

*   Le script `tests/step_08_validation.sh` s'exécute avec succès et affiche "PASS".
*   L'application Fablab est accessible via HTTP et HTTPS.
*   Le Pod Nginx contient deux conteneurs (nginx et sidecar) et les logs sont gérés par le sidecar.
*   Le ConfigMap Nginx est `immutable`.
*   Le Secret TLS est correctement créé et utilisé.
*   L'ADR documente clairement les choix techniques.

Bonne chance !