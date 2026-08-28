#!/bin/bash
set -euo pipefail

RESULT_FILE="tests/step_01_result.txt"
PASS_COUNT=0
FAIL_COUNT=0

mkdir -p tests
touch tests/step_01_result.txt

echo "=== Validation Étape 1 : Namespaces et isolation ===" >"$RESULT_FILE"

# Vérifier que les 4 namespaces existent
for ns in dev staging prod tools; do
  if kubectl get namespace "$ns" &>/dev/null; then
    echo "PASS: Namespace '$ns' existe" >>"$RESULT_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: Namespace '$ns' manquant" >>"$RESULT_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Vérifier les labels
for ns in dev staging prod tools; do
  LABELS=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.environment}' 2>/dev/null)
  if [ "$LABELS" == "$ns" ]; then
    echo "PASS: Labels du namespace '$ns' corrects" >>"$RESULT_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: Labels du namespace '$ns' incorrects (attendu: '$ns', obtenu: '$LABELS')" >>"$RESULT_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Vérifier qu'aucun pod ne tourne dans les namespaces (isolation initiale)
for ns in dev staging prod tools; do
  POD_COUNT=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
  if [ "$POD_COUNT" -eq 0 ]; then
    echo "PASS: Namespace '$ns' vide (aucun pod)" >>"$RESULT_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "WARN: Namespace '$ns' contient $POD_COUNT pods" >>"$RESULT_FILE"
  fi
done

# Résumé
echo "" >>"$RESULT_FILE"
echo "=== Résultat : $PASS_COUNT PASS, $FAIL_COUNT FAIL ===" >>"$RESULT_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS: Validation complète réussie" >>"$RESULT_FILE"
  exit 0
else
  echo "FAIL: Validation échouée" >>"$RESULT_FILE"
  exit 1
fi
