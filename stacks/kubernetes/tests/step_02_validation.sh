#!/bin/bash

# Couleurs pour une meilleure lisibilité
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour les ressources dans un namespace
check_ns() {
  local expected=$1      # "PASS" ou "FAIL"
  local user=$2          # Nom de l'utilisateur ou "system:serviceaccount:..."
  local group=$3         # Groupe (laisser vide pour les ServiceAccounts)
  local verb=$4
  local resource=$5
  local namespace=$6

  # Construction de la commande
  local cmd="kubectl auth can-i $verb $resource -n $namespace --as=$user"
  if [ -n "$group" ]; then
    cmd="$cmd --as-group=$group"
  fi

  # Exécution et récupération du résultat ("yes" ou "no")
  local result=$(eval $cmd 2>/dev/null)
  
  # Détermination du message de succès/échec
  if [ "$expected" == "PASS" ] && [ "$result" == "yes" ]; then
    echo -e "${GREEN}PASS${NC} | $user ($group) peut $verb $resource dans $namespace"
  elif [ "$expected" == "FAIL" ] && [ "$result" == "no" ]; then
    echo -e "${GREEN}PASS${NC} | $user ($group) NE PEUT PAS $verb $resource dans $namespace (conforme)"
  else
    echo -e "${RED}FAIL${NC} | $user ($group) - Attendu $expected, obtenu '$result' pour $verb $resource dans $namespace"
  fi
}

# Fonction pour les ressources cluster (sans namespace)
check_cluster() {
  local expected=$1
  local user=$2
  local group=$3
  local verb=$4
  local resource=$5

  local cmd="kubectl auth can-i $verb $resource --as=$user --as-group=$group"
  local result=$(eval $cmd 2>/dev/null)

  if [ "$expected" == "PASS" ] && [ "$result" == "yes" ]; then
    echo -e "${GREEN}PASS${NC} | $user ($group) peut $verb $resource (cluster)"
  elif [ "$expected" == "FAIL" ] && [ "$result" == "no" ]; then
    echo -e "${GREEN}PASS${NC} | $user ($group) NE PEUT PAS $verb $resource (cluster, conforme)"
  else
    echo -e "${RED}FAIL${NC} | $user ($group) - Attendu $expected, obtenu '$result' pour $verb $resource (cluster)"
  fi
}

echo "============================================="
echo "   VALIDATION RBAC - EXERCICE 1 (CKA)        "
echo "============================================="
echo ""

# ==========================================
# 1. TEST DU ROLE DEVELOPPER (dev & staging)
# ==========================================
echo -e "${YELLOW}--- TEST DEVELOPER (group: developer-grp) ---${NC}"
check_ns PASS developer-grp developer-grp get pods dev
check_ns PASS developer-grp developer-grp create deployments.apps dev
check_ns PASS developer-grp developer-grp update services dev
check_ns PASS developer-grp developer-grp patch configmaps dev
check_ns PASS developer-grp developer-grp get secrets staging
check_ns FAIL developer-grp developer-grp delete pods dev
check_ns FAIL developer-grp developer-grp delete pods staging
check_ns FAIL developer-grp developer-grp get pods prod
check_ns FAIL developer-grp developer-grp get pods tools
check_ns FAIL developer-grp developer-grp create roles.rbac.authorization.k8s.io dev

# ==========================================
# 2. TEST DU ROLE QA (staging)
# ==========================================
echo ""
echo -e "${YELLOW}--- TEST QA (group: qa-grp) ---${NC}"
check_ns PASS qa-grp qa-grp get pods staging
check_ns PASS qa-grp qa-grp get pods/log staging
check_ns PASS qa-grp qa-grp get services staging
check_ns PASS qa-grp qa-grp get configmaps staging
check_ns PASS qa-grp qa-grp get deployments.apps staging
check_ns FAIL qa-grp qa-grp create pods staging
check_ns FAIL qa-grp qa-grp delete services staging
check_ns FAIL qa-grp qa-grp update deployments.apps staging

# ==========================================
# 3. TEST DU ROLE SRE (prod) + CLUSTER
# ==========================================
echo ""
echo -e "${YELLOW}--- TEST SRE (group: sre-grp) ---${NC}"
check_ns PASS sre-grp sre-grp delete pods prod
check_ns PASS sre-grp sre-grp create pods/exec prod
check_ns PASS sre-grp sre-grp get events prod
check_ns PASS sre-grp sre-grp delete resourcequotas prod
check_ns FAIL sre-grp sre-grp create roles.rbac.authorization.k8s.io prod
check_cluster PASS sre-grp sre-grp get nodes
check_cluster PASS sre-grp sre-grp get persistentvolumes

# ==========================================
# 4. TEST DU SERVICE ACCOUNT CI/CD
# ==========================================
echo ""
echo -e "${YELLOW}--- TEST CI/CD (ServiceAccounts) ---${NC}"
check_ns PASS system:serviceaccount:dev:ci-cd-dev "" create deployments.apps dev
check_ns PASS system:serviceaccount:dev:ci-cd-dev "" update services dev
check_ns PASS system:serviceaccount:staging:ci-cd-staging "" create deployments.apps staging
check_ns PASS system:serviceaccount:staging:ci-cd-staging "" update services staging
check_ns FAIL system:serviceaccount:dev:ci-cd-dev "" get pods dev
check_ns FAIL system:serviceaccount:dev:ci-cd-dev "" create deployments.apps prod
check_ns FAIL system:serviceaccount:staging:ci-cd-staging "" delete services staging

echo ""
echo "============================================="
echo "   FIN DE LA VALIDATION                       "
echo "============================================="

