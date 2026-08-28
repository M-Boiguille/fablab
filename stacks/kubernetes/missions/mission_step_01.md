# Mission Étape 1 — Namespaces et isolation des environnements

## Objectif

Créer une structure de namespaces cohérente pour séparer les environnements **dev**, **staging**, **prod** et **tools**, et comprendre les implications d'isolation logique dans Kubernetes.

---

## 📖 A lire

### Livres & Documentation
- **Kubernetes in Action** — chapitre sur les Namespaces
- **Documentation officielle Kubernetes** — section Namespaces
- **Patterns** — un namespace par équipe et par environnement

### Modules KodeKloud
- **CKA** : Namespaces
- **CKAD** : Namespaces et context

---

## 🛠️ A créer

### 1. Manifest des namespaces (`namespaces.yaml`)

**Exigences :**
- Définir 4 namespaces : `dev`, `staging`, `prod`, `tools`
- Chaque namespace doit porter des **labels** permettant de l'identifier clairement (ex: environnement, équipe responsable)
- Utiliser une **convention de nommage** cohérente et documentée

**Critères d'acceptation :**
- Les 4 namespaces existent et sont visibles via `kubectl get namespaces`
- Chaque namespace possède au moins 2 labels distincts
- La convention de nommage est expliquée dans l'ADR

---

### 2. ADR — Décision d'architecture (`infra/adrs/adr_step_01_final.md`)

**Exigences :**
- Documenter le **choix de la stratégie de découpage** (par environnement, par équipe, hybride)
- Justifier la **convention de nommage** retenue
- Lister les **risques** identifiés et les **mitigations** associées
- Expliquer ce que l'isolation logique **permet** et **ne permet pas** (notamment en termes de sécurité réseau)

**Critères d'acceptation :**
- L'ADR suit le format standard (Contexte, Décision, Conséquences)
- Au moins 2 alternatives ont été évaluées avant de choisir
- Un risque métier est explicitement documenté

---

### 3. Script de validation (`tests/step_01_validation.sh`)

**Exigences :**
- Vérifier que les 4 namespaces existent
- Vérifier que chaque namespace possède les labels attendus
- Vérifier que le namespace courant (`kubectl config current-context`) pointe vers le bon namespace
- Générer un fichier de résultat `tests/step_01_result.txt` contenant le marqueur **PASS** ou **FAIL**

**Critères d'acceptation :**
- Le script est **exécutable** (`chmod +x`)
- Il retourne un code de sortie `0` en cas de succès, `1` en cas d'échec
- Le fichier de résultat est généré automatiquement

---

## 📦 A livrer

### Preuves attendues
1. Les 4 namespaces créés et visibles
2. L'ADR documenté et validé
3. Le script de validation fonctionnel
4. Le fichier `tests/step_01_result.txt` contenant **PASS**

### Commandes de validation
```bash
# Vérifier la présence des namespaces
kubectl get namespaces

# Vérifier les labels d'un namespace
kubectl get namespace dev --show-labels

# Exécuter le script de validation
./tests/step_01_validation.sh

# Vérifier le résultat
cat tests/step_01_result.txt
```

### Marqueurs de réussite
- [ ] Les 4 namespaces sont créés avec les labels appropriés
- [ ] L'ADR explique clairement la stratégie et les risques
- [ ] Le script de validation retourne **PASS**
- [ ] Vous pouvez expliquer oralement ce que l'isolation par namespace **garantit** et ce qu'elle **ne garantit pas**

---

## ⚠️ Risque métier identifié

**Risque** : Une mauvaise isolation entre environnements peut entraîner une **interférence entre la production et le développement**, causant des incidents en prod suite à des tests effectués dans le mauvais namespace.

**Question à se poser** : Comment votre convention de nommage et vos labels permettent-ils de **prévenir** ce risque dès la création des ressources ?

---

## ⏱️ Estimation

**Durée estimée : 2 à 3 heures** (lecture + création des artefacts + validation)

---

## 🎯 Critères de complétion

Cette étape est considérée comme terminée lorsque :
1. Le fichier `infra/adrs/adr_step_01_final.md` existe et documente la décision
2. Le fichier `tests/step_01_validation.sh` est exécutable et fonctionnel
3. Le fichier `tests/step_01_result.txt` contient **PASS**
4. Vous pouvez répondre aux questions suivantes :
   - Quelle est la différence entre isolation **logique** et isolation **physique** ?
   - Pourquoi ne pas créer un namespace par microservice ?
   - Comment les namespaces interagissent-ils avec le RBAC (étape 2) ?