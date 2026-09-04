#!/bin/bash

KUSTOMIZE_DIR="$HOME/fablab/stacks/kubernetes/infra/overlays/tests"

trap 'kubectl delete -k "$KUSTOMIZE_DIR" --ignore-not-found' EXIT

kubectl apply -k "$KUSTOMIZE_DIR"

# VARIABLES
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

NAMESPACE="dev"
DEPLOYMENT="nginx"
PROM_LABEL="app=prometheus"
GRAFANA_LABEL="app=grafana"

RESULT_FILE="$HOME/fablab/stacks/kubernetes/tests/step_04_result.txt"
LOG_FILE=$(mktemp)

PASS_COUNT=0
FAIL_COUNT=0

# FONCTIONS
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_pass() {
  local message="$1"
  echo -e "${GREEN}PASS${NC} | $message"
  echo "[$(timestamp)] PASS | $message" >>"$LOG_FILE"
  PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
  local message="$1"
  echo -e "${RED}FAIL${NC} | $message"
  echo "[$(timestamp)] FAIL | $message" >>"$LOG_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_not_empty() {
  local description="$1"
  local command="$2"
  local result
  result=$(eval "$command" 2>/dev/null)
  if [ -n "$result" ]; then
    log_pass "$description"
  else
    log_fail "$description (missing or empty)"
  fi
}

count_ready_pods() {
  local ns="$1"
  local label="$2"
  kubectl get pods -n "$ns" -l "$label" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null |
    grep -c '^True$' || true
}

get_pods() {
  mapfile -t pods < <(
    kubectl get pods -n "$NAMESPACE" -l "app=$DEPLOYMENT" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  )
}

wait_nginx_running() {
  local pod="$1"
  while true; do
    running=$(kubectl get pod "$pod" -n "$NAMESPACE" \
      -o jsonpath='{.status.containerStatuses[?(@.name=="nginx")].state.running}' 2>/dev/null)
    [ -n "$running" ] && return 0
    sleep 1
  done
}

# Fonction simplifiée pour manipuler index.html
manage_index() {
  local pod="$1"
  local action="$2"  # "remove" ou "create"
  wait_nginx_running "$pod"
  if [ "$action" == "remove" ]; then
    kubectl exec -n "$NAMESPACE" "pod/$pod" -c nginx -- rm -f /usr/share/nginx/html/index.html
  else
    kubectl exec -n "$NAMESPACE" "pod/$pod" -c nginx -- touch /usr/share/nginx/html/index.html
  fi
}

get_restart_count() {
  local pod="$1"
  kubectl get pod "$pod" -n "$NAMESPACE" \
    -o jsonpath='{.status.containerStatuses[?(@.name=="nginx")].restartCount}'
}

# CODE
echo "========================================="
echo "--   STEP 04 - VALIDATION SCRIPT       --"
echo "========================================="
echo "# Namespace: $NAMESPACE"
echo "# Deployment: $DEPLOYMENT"
echo "--- Testing Deployment Probes ---"

# 1. ATTENTE DES 3 PODS READY
echo "--- Attente que les 3 Pods soient Ready ---"
while true; do
  get_pods
  READY_COUNT=$(count_ready_pods "$NAMESPACE" "app=$DEPLOYMENT")
  echo -ne "\rPods détectés : ${#pods[@]} | Ready : $READY_COUNT/3"
  
  # Préparer les pods pour le test
  for pod in "${pods[@]}"; do
    [ -n "$pod" ] && manage_index "$pod" "create"
  done
  
  READY_COUNT=$(count_ready_pods "$NAMESPACE" "app=$DEPLOYMENT")
  if ((READY_COUNT == 3)); then
    echo
    log_pass "Les 3 Pods de '$DEPLOYMENT' sont Ready"
    break
  fi
  sleep 1
done

# 2. FIGER LES 3 PODS
get_pods
echo
echo "Pods utilisés pour le test :"
for pod in "${pods[@]}"; do
  echo "  - $pod"
done

# 3-4. VERIFICATION DES PROBES
check_not_empty \
  "Deployment '$DEPLOYMENT' has a readinessProbe" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o json | jq -r '.spec.template.spec.containers[] | select(.name==\"nginx\") | .readinessProbe // empty'"

check_not_empty \
  "Deployment '$DEPLOYMENT' has a livenessProbe" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o json | jq -r '.spec.template.spec.containers[] | select(.name==\"nginx\") | .livenessProbe // empty'"

# 5. SAUVEGARDE DES RESTART COUNTS
declare -A RESTARTS_BEFORE
echo
echo "--- Restart count initial ---"
for pod in "${pods[@]}"; do
  restart_count=$(get_restart_count "$pod")
  RESTARTS_BEFORE["$pod"]="$restart_count"
  echo "  $pod : $restart_count restart(s)"
done

# 6. UNLIVE LES 3 PODS
echo
echo "--- Unlive des 3 Pods ---"
for pod in "${pods[@]}"; do
  manage_index "$pod" "remove"
done

# 7. ATTENTE DU RESTART PAR LIVENESS PROBE
echo
echo "--- Attente du déclenchement des liveness probes ---"
while true; do
  RESTARTED_COUNT=0
  for pod in "${pods[@]}"; do
    before="${RESTARTS_BEFORE[$pod]}"
    after=$(get_restart_count "$pod")
    if [[ "$after" =~ ^[0-9]+$ ]] && [[ "$before" =~ ^[0-9]+$ ]] && ((after > before)); then
      RESTARTED_COUNT=$((RESTARTED_COUNT + 1))
    fi
  done
  echo -ne "\rPods redémarrés : $RESTARTED_COUNT/3"
  if ((RESTARTED_COUNT == 3)); then
    echo
    log_pass "Les liveness probes ont redémarré les 3 conteneurs"
    break
  fi
  sleep 1
done

# 8. RELIVE LES 3 PODS
echo
echo "--- Relive des 3 Pods ---"
for pod in "${pods[@]}"; do
  manage_index "$pod" "create"
done

# 9. ATTENTE DU RETOUR EN READY
echo
echo "--- Attente que les 3 Pods redeviennent Ready ---"
while true; do
  READY_COUNT=0
  for pod in "${pods[@]}"; do
    ready=$(kubectl get pod "$pod" -n "$NAMESPACE" \
      -o jsonpath='{.status.containerStatuses[?(@.name=="nginx")].ready}' 2>/dev/null)
    [ "$ready" == "true" ] && READY_COUNT=$((READY_COUNT + 1))
  done
  echo -ne "\rPods Ready : $READY_COUNT/3"
  if ((READY_COUNT == 3)); then
    echo
    log_pass "Les 3 Pods sont de nouveau Ready"
    break
  fi
  sleep 1
done

# 10. OBSERVABILITE
echo
echo "--- Testing Observability Stack ---"
PROM_READY=$(count_ready_pods "tools" "$PROM_LABEL")
kubectl get pods -n tools

if [ "$PROM_READY" -ge 1 ]; then
  log_pass "Prometheus is Ready in namespace 'tools' ($PROM_READY pod(s))"
else
  log_fail "Prometheus should be Ready in namespace 'tools'"
fi

GRAFANA_READY=$(count_ready_pods "tools" "$GRAFANA_LABEL")
if [ "$GRAFANA_READY" -ge 1 ]; then
  log_pass "Grafana is Ready in namespace 'tools' ($GRAFANA_READY pod(s))"
else
  log_fail "Grafana should be Ready in namespace 'tools'"
fi

# 11. RESULTAT
echo
echo "========================================="
echo "--   VALIDATION COMPLETE               --"
echo "========================================="
echo "# PASS: $PASS_COUNT"
echo "# FAIL: $FAIL_COUNT"

SUMMARY_TS=$(timestamp)
FINAL_TS=$(timestamp)

{
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
  echo "--- Summary ---"
  echo "[$SUMMARY_TS] Step 04 validation: $PASS_COUNT passed, $FAIL_COUNT failed"
  cat "$LOG_FILE"
  echo "# PASS: $PASS_COUNT"
  echo "# FAIL: $FAIL_COUNT"
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "[$FINAL_TS] # PASS | Step 04 validation successful"
  else
    echo "[$FINAL_TS] # FAIL | Step 04 validation failed"
  fi
} >"$RESULT_FILE"

rm -f "$LOG_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}OVERALL: PASS${NC}"
  exit 0
else
  echo -e "${RED}OVERALL: FAIL${NC}"
  exit 1
fi
