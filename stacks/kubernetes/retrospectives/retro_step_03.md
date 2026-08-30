# Rétrospective - Étape 03 : Déploiements basiques avec RollingUpdate

**Date :** [Date de la rétrospective]  
**Participants :** Équipe plateforme, SRE, Dev  
**Statut :** ✅ Validé (13/13 checks PASS)

---

## 1. Ce qui s'est bien passé

### ✅ Découplage configuration / image via ConfigMap
L'utilisation d'un `ConfigMap` pour la configuration Nginx a permis de séparer proprement la configuration applicative de l'image du conteneur. Cette approche évite toute dépendance au filesystem des nœuds et facilite les modifications de configuration sans reconstruire l'image.

### ✅ Stratégie RollingUpdate maîtrisée
Le choix de `maxUnavailable: 1` et `maxSurge: 1` a permis de maintenir la disponibilité du service pendant les mises à jour, tout en limitant la consommation temporaire de ressources. La validation a confirmé que les 3 replicas étaient prêts et que le Service avait bien 3 endpoints actifs.

### ✅ Sécurité renforcée dès le départ
L'application des contrôles de sécurité (`runAsNonRoot`, `allowPrivilegeEscalation: false`, drop de toutes les capabilities) dès cette étape est un excellent réflexe. Cela évite de devoir corriger des déploiements existants plus tard, ce qui est souvent plus complexe.

---

## 2. Ce qui a été difficile

### ⚠️ Dimensionnement des ressources
Les valeurs initiales de CPU et mémoire sont des estimations pour une application de démonstration. Il a été difficile de déterminer des valeurs pertinentes sans données de consommation réelles. Ce point reste à affiner avec l'observabilité (étape 4).

### ⚠️ Gestion des compromis entre disponibilité et ressources
Le choix de `maxSurge: 1` implique qu'un Pod supplémentaire peut être créé temporairement (jusqu'à 4 Pods pour 3 replicas). Il a fallu s'assurer que le cluster dispose de la marge nécessaire, ce qui n'est pas toujours évident à évaluer sans outils de monitoring.

---

## 3. Leçons apprises

### 📚 L'épinglage par digest est une bonne pratique à généraliser
L'utilisation de `nginx:1.30.4@sha256:...` avec `imagePullPolicy: IfNotPresent` garantit l'immutabilité de l'image. Cette pratique devrait être systématique, même en dev, pour éviter les surprises lors des recréations de Pods.

### 📚 La revue SRE en amont fait gagner du temps
L'amendement de l'ADR step 02 (RBAC) et les ajustements de sécurité ont été intégrés dès cette étape. Cette revue croisée permet d'anticiper les problèmes plutôt que de les corriger après coup.

### 📚 La séparation configuration / application est un investissement
Bien que le ConfigMap ajoute une ressource à gérer, il simplifie considérablement les mises à jour de configuration et évite les problèmes de dépendance au nœud. C'est un investissement qui porte ses fruits sur le long terme.

---

## 4. Risque reporté

### 🔴 Dimensionnement des ressources basé sur des estimations

**Description :** Les `requests` et `limits` actuels sont des estimations pour une application de démonstration. En production, une sous-estimation pourrait entraîner des problèmes de performance ou des évictions de Pods, tandis qu'une sur-estimation gaspillerait des ressources.

**Mitigation :**
- Mettre en place l'observabilité (étape 4) pour mesurer la consommation réelle
- Revoir le dimensionnement après 2 semaines de données de production
- Utiliser le Vertical Pod Autoscaler (VPA) en mode recommandation pour affiner les valeurs

---

## 5. Conseil pour la prochaine étape

### 🎯 Préparez les probes en pensant aux scénarios réels

Pour l'étape 4 (Probes et observabilité), ne vous contentez pas de configurer des probes qui répondent "OK". Testez des scénarios de dégradation réelle :
- Que se passe-t-il si l'application répond lentement (latence > timeout) ?
- Que se passe-t-il si une dépendance (base de données, API externe) est indisponible ?
- Comment les probes interagissent-elles avec le RollingUpdate ?

Ces tests vous permettront de configurer des probes pertinentes et d'éviter des faux positifs/négatifs en production.

---

## 6. Décisions clés

| Décision | Justification | Impact |
|----------|---------------|--------|
| **Deployment avec 3 replicas** | Redondance et capacité de service pendant les mises à jour | Disponibilité accrue, consommation de ressources multipliée par 3 |
| **Stratégie RollingUpdate (maxUnavailable: 1, maxSurge: 1)** | Équilibre entre disponibilité et consommation de ressources | Jusqu'à 4 Pods temporaires pendant les rollouts |
| **Service ClusterIP (port 8080 → targetPort 80)** | Exposition limitée au cluster, pas d'exposition externe nécessaire | Sécurité renforcée, accès interne uniquement |
| **ConfigMap pour la configuration Nginx** | Découplage configuration / image, indépendance du filesystem des nœuds | Facilité de modification, portabilité des Pods |
| **Image épinglée par digest (nginx:1.30.4@sha256:...)** | Immutabilité garantie, pas de surprise lors des recréations | Reproductibilité des déploiements |
| **Contrôles de sécurité appliqués (runAsNonRoot, drop capabilities)** | Conformité aux bonnes pratiques de sécurité dès le départ | Réduction de la surface d'attaque |
| **Labels standardisés (app, environment, team, version, managed-by)** | Traçabilité et gestion cohérente des ressources | Facilite la sélection et le filtrage des ressources |

---

## Actions de suivi

- [ ] Intégrer les données de consommation réelle après l'étape 4 pour ajuster les ressources
- [ ] Documenter les scénarios de test des probes pour l'étape 4
- [ ] Prévoir le passage à un registre privé avec signature Cosign (étape 12)
- [ ] Planifier l'ajout d'un PodDisruptionBudget en production

---

*Rétrospective générée après validation de l'étape 03 - 13/13 checks PASS*