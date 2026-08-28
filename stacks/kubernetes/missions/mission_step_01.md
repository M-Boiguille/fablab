# Mission Étape 1 : Namespaces et isolation des environnements

## Objectif

Mettre en place une structure de namespaces claire et cohérente pour isoler les environnements (dev, staging, prod) et les outils transverses (tools), conformément aux bonnes pratiques d'entreprise.

---

## 📚 À lire

### Documentation officielle
- **Kubernetes in Action** — Chapitre sur les Namespaces (concepts, cas d'usage)
- **Documentation Kubernetes** : [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)

### Patterns d'entreprise
- **Pattern recommandé** : un namespace par équipe ET par environnement (ex: `dev-team-a`, `prod-team-a`)
- **Convention de nommage** : `{environment}-{team}` ou `{team}-{environment}` — à définir et documenter

### Modules KodeKloud
- **CKA** : Namespaces (concepts et manipulation)
- **CKAD** : Namespaces et context (changement de contexte, kubectl config)

---

## 🛠️ À créer

### 1. Manifests YAML des namespaces

Créez le dossier `infra/namespaces/` avec les fichiers suivants :

**`infra/namespaces/00-namespaces.yaml`**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    environment: dev
    team: platform
    managed-by: terraform
---
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    environment: staging
    team: platform
    managed-by: terraform
---
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    environment: prod
    team: platform
    managed-by: terraform
---
apiVersion: v1
kind: Namespace
metadata:
  name: tools
  labels:
    environment: tools
    team: platform
    managed-by: terraform
```

### 2. Script de validation

**`tests/step_01_validation.sh`**
```bash
#!/bin/bash
set -euo pipefail

RESULT_FILE="tests/step_01_result.txt"
PASS_COUNT=0
FAIL_COUNT=0

echo "=== Validation Étape 1 : Namespaces et isolation ===" > "$RESULT_FILE"

# Vérifier que les 4 namespaces existent
for ns in dev staging prod tools; do
  if kubectl get namespace "$ns" &>/dev/null; then
    echo "PASS: Namespace '$ns' existe" >> "$RESULT_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: Namespace '$ns' manquant" >> "$RESULT_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Vérifier les labels
for ns in dev staging prod tools; do
  LABELS=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.environment}' 2>/dev/null)
  if [ "$LABELS" == "$ns" ] || [ "$ns" == "tools" ] && [ "$LABELS" == "tools" ]; then
    echo "PASS: Labels du namespace '$ns' corrects" >> "$RESULT_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: Labels du namespace '$ns' incorrects (attendu: $ns, obtenu: $LABELS)" >> "$RESULT_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Vérifier qu'aucun pod ne tourne dans les namespaces (isolation initiale)
for ns in dev staging prod tools; do
  POD_COUNT=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
  if [ "$POD_COUNT" -eq 0 ]; then
    echo "PASS: Namespace '$ns' vide (aucun pod)" >> "$RESULT_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "WARN: Namespace '$ns' contient $POD_COUNT pods" >> "$RESULT_FILE"
  fi
done

# Résumé
echo "" >> "$RESULT_FILE"
echo "=== Résultat : $PASS_COUNT PASS, $FAIL_COUNT FAIL ===" >> "$RESULT_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS: Validation complète réussie" >> "$RESULT_FILE"
  exit 0
else
  echo "FAIL: Validation échouée" >> "$RESULT_FILE"
  exit 1
fi
```

### 3. ADR (Architecture Decision Record)

**`infra/adrs/adr_step_01_final.md`**
```markdown
# ADR-001 : Structure des namespaces pour isolation des environnements

## Statut
Accepté

## Date
2026-08-28

## Contexte
Le cluster Kubernetes mutualisé doit héberger plusieurs environnements (dev, staging, prod) et des outils transverses. Sans isolation claire, les risques sont :
- Interférence entre environnements (un déploiement dev impacte la prod)
- Difficulté de gestion des quotas et des coûts
- Risque de sécurité (accès croisés non maîtrisés)

## Décision
Nous adoptons une structure de namespaces par environnement :
- `dev` : développement
- `staging` : pré-production
- `prod` : production
- `tools` : outils transverses (monitoring, CI/CD, etc.)

Chaque namespace porte des labels standardisés (`environment`, `team`, `managed-by`) pour faciliter l'automatisation et la gouvernance.

## Conséquences
- **Positives** : isolation logique claire, base pour RBAC et quotas, simplicité de gestion
- **Négatives** : nécessite une discipline stricte de nommage, risque de prolifération si non gouverné
- **Risques** : un namespace mal configuré peut exposer des ressources sensibles

## Alternatives considérées
1. **Un seul namespace** : rejeté — aucun isolation, risques majeurs
2. **Namespaces par équipe uniquement** : rejeté — pas d'isolation entre environnements
3. **Clusters séparés** : rejeté — coût et complexité opérationnelle trop élevés
```

---

## 📦 À livrer

### Commandes de validation

```bash
# 1. Appliquer les namespaces
kubectl apply -f infra/namespaces/00-namespaces.yaml

# 2. Vérifier la création
kubectl get namespaces

# 3. Vérifier les labels
kubectl get namespace dev --show-labels

# 4. Exécuter le script de validation
chmod +x tests/step_01_validation.sh
./tests/step_01_validation.sh

# 5. Vérifier le résultat
cat tests/step_01_result.txt
```

### Tests attendus
- ✅ Les 4 namespaces (`dev`, `staging`, `prod`, `tools`) existent
- ✅ Les labels `environment` sont correctement appliqués
- ✅ Aucun pod ne tourne dans ces namespaces (état initial propre)
- ✅ Le script de validation retourne `PASS` pour tous les checks

### Preuves à fournir
- `tests/step_01_result.txt` contenant les résultats de validation
- `infra/adrs/adr_step_01_final.md` documentant la décision d'architecture
- Les manifests YAML des namespaces versionnés dans le repo

---

## ⚠️ Risque métier

**Un namespace mal configuré ou une absence de convention de nommage peut entraîner un déploiement accidentel en production.** Par exemple, un développeur croyant déployer en `dev` pourrait pousser du code non testé en `prod` si les namespaces ne sont pas clairement identifiés et isolés. Cela peut causer une interruption de service pour les clients et des pertes financières significatives.

---

## ⏱️ Estimation de temps

| Activité | Durée estimée |
|----------|---------------|
| Lecture des ressources | 1h30 |
| Création des manifests | 30 min |
| Rédaction de l'ADR | 45 min |
| Script de validation et tests | 45 min |
| **Total** | **3h30** |

---

## 🎯 Critères de complétion

- [ ] Les 4 namespaces sont créés avec les labels appropriés
- [ ] Le script `tests/step_01_validation.sh` passe avec 100% de réussite
- [ ] L'ADR est rédigé et versionné dans `infra/adrs/`
- [ ] Le fichier `tests/step_01_result.txt` est généré et contient les marqueurs `PASS`
- [ ] La structure de dossiers est conforme aux standards du projet

---

**Prochaine étape** : RBAC et moindre privilège (modélisation des accès par rôle) — à ne pas anticiper avant validation de cette étape.