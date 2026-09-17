# Étape 6 — Stratégies avancées : Blue/Green et Canary

## Objectif de la mission

Mettre en place des stratégies de déploiement Blue/Green et Canary pour une application critique, en garantissant zéro interruption de service et une capacité de rollback immédiat.

---

## 📚 A lire

### Concepts fondamentaux
- **Stratégie Blue/Green** : deux environnements identiques (Blue = actuel, Green = nouveau), bascule du trafic via le Service, rollback immédiat en cas de problème.
- **Stratégie Canary** : déploiement progressif (10%, 50%, 100%), observation des métriques à chaque palier, décision de continuer ou d'annuler.
- **Différences clés** : Blue/Green = bascule binaire (tout ou rien), Canary = progression graduelle avec validation continue.
- **Ressources Kubernetes impliquées** : Deployments, Services, Ingress (si applicable), et comment le Service sélectionne les pods (labels/selectors).

### Questions à se poser avant de commencer
- Comment le Service achemine-t-il le trafic vers les pods ? Quel rôle jouent les labels et selectors ?
- Quelle est la différence entre une mise à jour de Deployment (RollingUpdate) et une stratégie Blue/Green ?
- Comment simuler une panne pour tester le rollback ?

---

## 🛠 A créer

### 1. Manifests Blue/Green pour l'environnement staging

**Fichiers attendus** (dans `stacks/kubernetes/apps/` ou équivalent) :
- Deployment pour la version **blue** (actuelle)
- Deployment pour la version **green** (nouvelle)
- Service partagé permettant la bascule

**Exigences** :
- Les deux Deployments doivent être identiques en configuration (mêmes probes, ressources, quotas respectés)
- La seule différence entre blue et green doit être l'**image** (version différente) et les **labels**
- Le Service doit pouvoir basculer entre blue et green **sans modification des Deployments**
- Les ResourceQuotas du namespace staging (étape 5) doivent être respectées

**Critères d'acceptation** :
- [ ] Le Service pointe initialement vers blue (100% du trafic)
- [ ] La bascule vers green se fait par une seule commande `kubectl patch` ou `kubectl apply` sur le Service
- [ ] Le rollback vers blue est possible en moins de 30 secondes
- [ ] Aucune interruption de service pendant la bascule (vérifiable via les logs ou un curl continu)

---

### 2. Manifests Canary pour l'environnement dev

**Fichiers attendus** :
- Deployment pour la version stable
- Deployment pour la version canary (nouvelle)
- Service routant vers les deux versions

**Exigences** :
- Le Service doit router le trafic vers **les deux versions simultanément**
- Le pourcentage de trafic vers canary doit être contrôlable (via le nombre de réplicas ou un autre mécanisme)
- Les deux versions doivent être **distinguables** (réponse HTTP différente, par exemple)
- La version canary doit pouvoir être **scalée progressivement** (1 replica → 2 → 3) pour augmenter le pourcentage de trafic

**Critères d'acceptation** :
- [ ] Le Service route vers les pods stable ET canary simultanément
- [ ] En scalant canary de 1 à 2 réplicas, le pourcentage de trafic canary augmente
- [ ] Il est possible de **stopper complètement** le trafic canary en scalant à 0
- [ ] Les deux versions répondent correctement et sont identifiables

---

### 3. Script de validation : `tests/step_06_validation.sh`

**Exigences** :
- Script bash exécutable (`chmod +x`)
- Utilise `kubectl` pour vérifier l'état des ressources
- Teste les scénarios suivants :
  - Vérification que les Deployments blue/green/canary existent et sont prêts
  - Vérification que le Service blue/green pointe vers la bonne version
  - Test de bascule blue → green et vérification que le trafic est routé correctement
  - Test de rollback green → blue
  - Vérification que le Service canary route vers les deux versions
- Écrit le résultat dans `tests/step_06_result.txt` avec le mot-clé `PASS` en cas de succès

**Critères d'acceptation** :
- [ ] Le script s'exécute sans erreur
- [ ] Chaque vérification produit une sortie claire (OK/KO)
- [ ] Le fichier `tests/step_06_result.txt` contient `PASS` uniquement si toutes les vérifications réussissent
- [ ] Le script est **idempotent** (exécutable plusieurs fois sans effet de bord)

---

### 4. ADR final : `infra/adrs/adr_step_06_final.md`

**Exigences** :
- Documente la décision : quelle stratégie pour quel environnement (Blue/Green en staging, Canary en dev, ou l'inverse, et pourquoi)
- Compare les deux stratégies (avantages, inconvénients, cas d'usage)
- Justifie le choix en fonction du contexte (application critique, besoin de rollback rapide, etc.)
- Mentionne les risques identifiés et les mitigations
- Inclut les commandes de bascule/rollback utilisées (sans copier les manifests complets)

**Critères d'acceptation** :
- [ ] L'ADR suit le format standard (Contexte, Décision, Conséquences)
- [ ] La décision est justifiée par des critères objectifs (temps de rollback, exposition au risque, coût)
- [ ] Les commandes de bascule et rollback sont documentées
- [ ] L'ADR mentionne les limites de l'approche choisie

---

## 📦 A livrer

### Preuves attendues
1. Les manifests Blue/Green et Canary versionnés dans le dépôt
2. Le script `tests/step_06_validation.sh` exécutable
3. Le fichier `tests/step_06_result.txt` contenant `PASS`
4. L'ADR `infra/adrs/adr_step_06_final.md` complété

### Commandes de validation
```bash
# Exécuter le script de validation
./tests/step_06_validation.sh

# Vérifier le résultat
cat tests/step_06_result.txt
# Doit contenir : PASS

# Vérifier les ressources déployées
kubectl get deployments -n staging -l strategy=blue-green
kubectl get deployments -n dev -l strategy=canary
```

### Marqueurs de réussite
- [ ] Le script de validation retourne `PASS`
- [ ] La bascule blue → green se fait sans interruption de service (testable avec un `while curl` en continu)
- [ ] Le rollback est immédiat (moins de 30 secondes)
- [ ] Le trafic canary est progressif et contrôlable
- [ ] L'ADR documente clairement la stratégie choisie et les commandes opérationnelles

---

## ⚠️ Risque métier à considérer

**Scénario** : Une mauvaise configuration de la stratégie Canary pourrait envoyer 50% du trafic de production vers une version instable, impactant potentiellement des clients réels. La stratégie Blue/Green, bien que plus coûteuse en ressources (double déploiement), offre un rollback immédiat et sans risque de perte de trafic partiel. Le choix entre les deux doit prendre en compte le coût de l'infrastructure vs le coût d'une erreur en production.

---

## ⏱ Estimation de temps

| Activité | Durée estimée |
|----------|---------------|
| Lecture et compréhension des concepts | 1h |
| Création des manifests Blue/Green | 1h30 |
| Création des manifests Canary | 1h30 |
| Tests manuels de bascule et rollback | 1h |
| Script de validation | 1h |
| Rédaction de l'ADR | 1h |
| **Total** | **~7h** |

---

## 📝 Notes finales

- Ne copiez pas les manifests existants de l'étape 3 sans comprendre les différences : les stratégies Blue/Green et Canary nécessitent une **séparation stricte** entre les Deployments et le Service.
- Testez les scénarios de panne : que se passe-t-il si green n'est pas prêt ? Si canary crash ?
- Documentez dans l'ADR les commandes exactes utilisées pour la bascule — c'est ce que les opérationnels utiliseront en production.