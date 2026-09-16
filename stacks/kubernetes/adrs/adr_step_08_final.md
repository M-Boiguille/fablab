# ADR 08 - ConfigMaps, Secrets et patterns multi-conteneurs

* **Statut :** Accepté
* **Date :** 2026-09-16
* **Auteur :** Équipe Plateforme Fablab
* **Contexte lié :** Étape 8 - ConfigMaps, Secrets et patterns multi-conteneurs

---

## 1. Contexte

Jusqu'ici, l'application Fablab servait son `index.html` depuis un ConfigMap minimal, la configuration Nginx restant largement embarquée dans l'image. Trois besoins apparaissent à cette étape :

1. **externaliser l'intégralité du `nginx.conf`** dans un ConfigMap afin de piloter la configuration sans reconstruire l'image (HTTP + HTTPS) ;
2. **exposer l'application en HTTPS** via un certificat TLS, ce qui suppose un Secret de type `kubernetes.io/tls` et sa terminaison dans le conteneur Nginx ;
3. **collecter et faire tourner les logs Nginx** sans ajouter de logique applicative dans le conteneur Nginx, en s'appuyant sur un volume partagé et un conteneur dédié.

Le risque métier reste concret : une configuration Nginx ou un certificat TLS mal gérés rendent l'application inaccessible en HTTPS et les incidents difficiles à diagnostiquer. La documentation Kubernetes désigne en outre l'**immuabilité des ConfigMaps** et la **gestion des Secrets** comme des points sensibles, qu'il convient de traiter explicitement.

Le contexte d'exécution reste un cluster **K3s mono-nœud**, ce qui pèse sur plusieurs choix ci-dessous (surge de rolling update et quota de pods, redémarrages imposés par l'immuabilité).

---

## 2. Décisions

### 2.1. ConfigMap Nginx étendu et immuable

On crée un ConfigMap `nginx-config` (namespace `dev`) contenant l'intégralité du fichier `nginx.conf`, avec deux blocs `server` : un en HTTP (port 80) et un en HTTPS (port 443, certificats montés depuis le Secret). Il est marqué `immutable: true`.

Justification de l'immuabilité :

* elle interdit toute modification accidentelle du contenu, en particulier en production ;
* elle évite au kubelet de maintenir un *watch* sur l'objet (moins de trafic vers l'API Server) ;
* elle est explicitement demandée par la mission et correspond au mode attendu d'une configuration « figée » versionnée.

En contrepartie, toute évolution de `nginx.conf` impose de **supprimer puis recréer** le ConfigMap : les pods doivent être redémarrés pour consommer la nouvelle version.

### 2.2. Secret TLS auto-signé

On crée un Secret `nginx-secret` de type `kubernetes.io/tls` contenant une paire `tls.crt` / `tls.key` **auto-signée**, montée dans le conteneur Nginx via un volume dédié (`/usr/share/nginx/certificates`). Ce choix est celui d'un environnement de développement : il évite de dépendre d'une autorité externe pour valider le parcours HTTPS de bout en bout. Les prochaines étapes viseront une gestion plus robuste des certificats (émission et renouvellement automatisés, par exemple via `cert-manager`).

### 2.3. Pattern *sidecar* pour la rotation des logs

On ajoute un conteneur `sidecar-nginx` (image `busybox`) partageant un volume `emptyDir` (`nginx-logs`) avec le conteneur `nginx`. Le conteneur `nginx` écrit ses logs sur ce volume ; le sidecar exécute une boucle shell qui archive et vide périodiquement `access.log` et `error.log`. C'est le pattern *sidecar* : un conteneur auxiliaire qui assiste le conteneur principal dans le même pod.

Ce choix tranche en faveur du découplage : le conteneur `nginx` reste minimal et n'embarque aucune logique de rotation.

### 2.4. Montage de la configuration via `subPath`

Le fichier `nginx.conf` est monté sur `/etc/nginx/nginx.conf` avec `subPath: nginx.conf` et `readOnly: true`. Le `subPath` évite de masquer tout le répertoire `/etc/nginx` (mime.types, etc.) par un simple fichier, et le `readOnly` garantit qu'aucun conteneur ne peut altérer la configuration servie. Cette combinaison est cohérente avec l'immuabilité choisie en 2.1 : dans les deux cas, la configuration est figée tant que le pod n'est pas recréé.

### 2.5. Durcissement des `securityContext`

Le pod définit `runAsNonRoot: true` et `fsGroup: 101`. Chaque conteneur (`html-file`, `sidecar-nginx`, `nginx`, `nginx-prometheus-exporter`) applique `allowPrivilegeEscalation: false`, `runAsNonRoot: true`, `runAsUser: 101` et un `capabilities.drop: [ALL]`. Le conteneur `nginx` conserve uniquement `NET_BIND_SERVICE` (via `capabilities.add`), nécessaire pour se lier aux ports privilégiés 80 et 443 tout en restant non-root.

---

## 3. Conséquences

**Positives**

* Le ConfigMap immuable sert de source de vérité figée ; toute dérive locale est impossible sans un acte explicite (delete + recreate).
* Le pattern *sidecar* découple la rotation des logs de l'application : Nginx reste mince et la logique auxiliaire est isolée dans son propre conteneur.
* Le Secret TLS est standardisé (`kubernetes.io/tls`) et monté dans le pod, ce qui rend le durcissement futur (rotation automatique) plus simple à intégrer.
* Le passage à 3 conteneurs par pod illustre concrètement le modèle de *pod* comme unité de co-scheduling et de partage de volumes.

**Risques et limites**

* **Immuabilité + `subPath` :** modifier `nginx.conf` exige de supprimer/recréer le ConfigMap **et** de redémarrer les pods. Aucune propagation « à chaud » n'est possible.
* **Surge de rolling update :** sur ce cluster K3s mono-nœud, le quota de pods du namespace `dev` limite le nombre de pods simultanés. Un `maxSurge: 1` combiné aux autres workloads peut être refusé (`exceeded quota: dev-ressources`), ce qui a nécessité de relever le quota `pods` (7 → 10) et d'ajuster les quotas CPU/mémoire.
* **Secret TLS auto-signé :** non adapté à la production (avertissement navigateur, pas de chaîne de confiance gérée). À remplacer à moyen terme.
* **Sidecar supplémentaire :** un conteneur de plus par pod consomme des ressources et reçoit, via `LimitRange`, des `requests`/`limits` par défaut. Le script shell de rotation reste simple et n'implémente pas de vraie compression/archivage.
* **Bug rencontré – cache kubelet sur K3s :** lors du test *break-it*, après suppression du ConfigMap `nginx-config` (`kubectl delete cm -n dev nginx-config`), les pods recréés via `k rollout restart` ou `k delete pods` ont démarré sans erreur. Le `describe pod` indiquait pourtant `Optional: false` sur le volume `nginx-config`, et `kubectl get cm -n dev` confirmait l'absence de l'objet. Aucun événement `FailedMount` n'a été généré. En inspectant le pod, la configuration servie était encore l'ancienne version de la ConfigMap, et la readiness probe `/hello` passait. Nous avons reproduit ce comportement plusieurs fois : suppression, recréation des pods, redémarrage complet de la stack (`k delete -k infra/ && k apply -k infra/`) ; à chaque fois les pods démarraient `3/3`.
    * **Tests réalisés (résumé)** :
        1. `kubectl delete cm -n dev nginx-config` → `kubectl get cm -n dev` montre bien que `nginx-config` est absent.
        2. `kubectl rollout restart deployment nginx -n dev` → nouveau pod `nginx-5dccb86f47-...` `3/3 Running` sans `FailedMount`.
        3. `kubectl describe pod <pod>` : volume `nginx-config` `Optional: false`, aucun événement d'erreur.
        4. `kubectl exec ... -- cat /etc/nginx/nginx.conf` : configuration personnalisée toujours présente.
        5. Après `kubectl delete -k infra/ && kubectl apply -k infra/` puis suppression de la CM et recréation des pods, le comportement se reproduit.
    * **Cause probable** : le kubelet K3s maintient un cache mémoire des ConfigMaps/Secrets alimenté par un informer (LIST/WATCH). La suppression n'est pas reflétée dans ce cache, soit parce que le watch est rompu, soit parce que le kubelet n'a pas resynchronisé. Le cache reste donc périmé et sert l'ancienne version.
    * **Correctif immédiat** : redémarrer le service k3s (`sudo systemctl restart k3s`) force la resynchronisation. Nous n'avons pas d'autre levier disponible dans l'environnement actuel pour purger ce cache à chaud.
    * **Impact** : le test *break-it* ne peut pas valider l'erreur attendue (`ContainerCreating` + `FailedMount`) tant que le cache kubelet n'est pas purgé. Ce comportement doit être pris en compte dans les scripts de validation et la documentation de debug.

---

## 4. Références

* `stacks/kubernetes/missions/mission_step_08.md`
* `stacks/kubernetes/adrs/adr_step_07_final.md` (pour la continuité des choix de scheduling et de durcissement)
* Documentation Kubernetes : [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/), [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/), [Patterns de conteneurs](https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/#container-patterns)
* Manifests associés :
  * `infra/apps/demo/nginx/configmap-nginx.yaml`
  * `infra/apps/demo/nginx/secret-tls-nginx.yaml`
  * `infra/apps/demo/nginx/deployment-nginx.yaml`
  * `infra/base/resource_quotas/resourcequota_dev.yaml`
* Validation : `tests/step_08_validation.sh` et `tests/step_08_result.txt`
