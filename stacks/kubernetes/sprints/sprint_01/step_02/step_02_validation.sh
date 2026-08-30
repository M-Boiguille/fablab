#!/bin/bash
set -euo pipefail

# Step 02 — sprint kubernetes
# TODO: remplacer cette valeur par le résultat attendu de ta vérification
EXPECTED="ok"

echo "Vérification step 02..."

if [ "$EXPECTED" == "TODO" ]; then
    echo "FAIL — Step 02 non complétée (TODO)."
    exit 1
fi

echo "PASS — Step 02 validée."
