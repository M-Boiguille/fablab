# ADR 07 - Scheduling avancé sur cluster K3s mono-nœud

* **Statut :** Accepté
* **Date :** 2025-05-18
* **Auteur :** Équipe Plateforme Fablab
* **Contexte lié :** Étape 7 - Scheduling avancé

---

## 1. Contexte

Le scheduler par défaut place les pods sans garantie de nœud, de priorité ni de cycle de vie. Pour la plateforme Fablab, quatre besoins sortent de ce cadre :

1. un agent de collecte de logs présent sur *chaque* nœud, sans déploiement manuel ;
2. une application Nginx critique protégée de l'éviction en cas de pression ;
3. un composant géré directement par le kubelet, hors API Server ;
4. un workload isolé sur un nœud « premium », sans machine supplémentaire.

Le cluster est aujourd'hui une instance **K3s mono-nœud**. Ce n'est pas anodin : un taint ou une affinité mal posés peuvent bloquer le seul nœud et laisser des pods en `Pending`. Les décisions ci-dessous visent donc à démontrer les mécanismes, à rester neutres pour le nœud unique et à passer à un cluster multi-nœuds sans réécrire les manifests.

---

## 2. Décisions

### 2.1. DaemonSet de collecte de logs

On déploie un `DaemonSet` dans `dev`, montant `/var/log/pods/` de l'hôte via un `hostPath`. C'est le seul contrôleur qui garantit une instance par nœud éligible et suit automatiquement les nœuds ajoutés. Sur un cluster mono-nœud, il ne crée donc qu'un pod, mais le comportement reste identique à l'échelle.

Le conteneur s'exécute en **root** : c'est nécessaire pour lire les logs de l'hôte sous `/var/log/pods/`. Ce choix est compensé par un durcissement explicite du `securityContext` :

- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- `readOnlyRootFilesystem: true`
- montage du `hostPath` en `readOnly: true`

Un conteneur compromis ne peut donc ni escalader ses privilèges, ni modifier ou supprimer les logs collectés.

### 2.2. Static Pod Nginx

On déploie Nginx en **Static Pod** en déposant un manifeste dans le répertoire de pods statiques du kubelet K3s (`/var/lib/rancher/k3s/agent/pod-manifests`). C'est le seul moyen de faire gérer un pod par le kubelet local sans passer par l'API Server. Le manifeste est déposé puis retiré par le script de validation : il n'a pas vocation à rester actif à ce stade.

### 2.3. PriorityClass pour l'application Fablab

On définit une `PriorityClass` `nginx` (valeur `1000`, `preemptionPolicy: Never`) dans `infra/apps/demo/nginx/priorityclass-nginx.yaml`, puis on la référence sur le déploiement Nginx de l'application Fablab (`dev`). La valeur reste volontairement dans la plage applicative (1000 à 10000) : une priorité applicative n'a pas à se situer dans la plage haute réservée aux composants système critiques du cluster. `preemptionPolicy: Never` empêche le scheduler d'expulser des pods existants : sur un cluster mono-nœud, une préemption agressive pourrait évincer des composants d'infrastructure au profit de cette workload non critique. Le manifeste séparé découple la politique de priorité du déploiement ; la priorité reste déclarée et vérifiable, sans introduire de risque d'éviction.

### 2.4. Placement sur nœud dédié (Affinity + Toleration)

Pour simuler un nœud « premium », on labellise le nœud avec `node-role.kubernetes.io/premium=true`, on y pose un taint `taint-color=yellow:NoSchedule`, et on crée un déploiement Nginx dédié (1 replica, namespace `default`) avec une `nodeAffinity` `requiredDuringSchedulingIgnoredDuringExecution` sur ce label et la toleration correspondante (`taint-color=yellow`). L'affinité attire le pod vers le nœud, la toleration autorise son placement malgré le taint : les deux sont complémentaires, et le mode `required` garantit qu'il ne part jamais ailleurs. Le namespace `default` isole cet objet temporaire de l'existant. Sur un seul nœud, le pod reste `Pending` en l'absence de label ou en présence d'un taint `taint-color=blue` non toléré, puis passe `Running` quand le label est présent et que la toleration correspond au taint `taint-color=yellow` ; le script de validation détaille ce comportement.

---

## 3. Conséquences

**Positives**

* Les manifests sont prêts pour un cluster multi-nœuds : le `DaemonSet` suit l'ajout de nœuds, les contraintes du nœud premium restent déclaratives.
* La `PriorityClass` vit dans son propre manifeste, indépendamment des déploiements.
* L'affinité + toleration est validée sans rendre le nœud inutilisable.

**Risques et limites**

* Sur mono-nœud, un label ou un taint mal posé peut bloquer la planification : ils sont retirés en fin de validation (via `tests/step_07_validation.sh`).
* Le `hostPath` du `DaemonSet` expose le système de fichiers hôte en lecture seule. L'exécution en root, compensée par un `securityContext` durci, demeure un privilège sensible ; tout élargissement de périmètre devra être justifié.
* Le taint `taint-color` est temporaire : le laisser en place perturberait la planification normale.
* Le Static Pod est déployé pour démonstration puis retiré ; son maintien éventuel relèvera d'une décision ultérieure.
