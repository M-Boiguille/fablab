#!/usr/bin/env bash
set -uo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
STACK_DIR="$(cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

RESULT_FILE="$SCRIPT_DIR/step_07_result.txt"
rm -f "$RESULT_FILE"

MANIFEST="$STACK_DIR/infra/apps/demo/tainted-nginx/deployment-nginx-tainted.yaml"
if [[ ! -f "$MANIFEST" ]]; then
  MANIFEST="$STACK_DIR/infra/apps/demo/tainted-nginx/tainted-nginx.yaml"
fi

STATIC_POD_SCRIPT="$STACK_DIR/infra/apps/demo/static-nginx/deploy-static-pod.sh"

LOG_ENTRIES=()
PASS_COUNT=0
FAIL_COUNT=0

log_pass() {
  local msg="$1"
  LOG_ENTRIES+=("PASS | $msg")
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS | $msg"
}

log_fail() {
  local msg="$1"
  LOG_ENTRIES+=("FAIL | $msg")
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL | $msg" >&2
}

write_result_file() {
  local status="PASS"
  local status_word="successful"
  if ((FAIL_COUNT > 0)); then
    status="FAIL"
    status_word="failed"
  fi

  {
    echo "$status"
    echo "--- Summary ---"
    for entry in "${LOG_ENTRIES[@]}"; do
      echo "$entry"
    done
    echo "# PASS: $PASS_COUNT"
    echo "# FAIL: $FAIL_COUNT"
    echo "# $status | Step 07 validation $status_word"
  } >"$RESULT_FILE"
}

NODE_NAME="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
if [[ -z "$NODE_NAME" ]]; then
  log_fail "No Kubernetes node found. Is kubectl configured and cluster running?"
  write_result_file
  exit 1
fi

cleanup() {
  if [[ -f "$MANIFEST" ]]; then
    kubectl delete -f "$MANIFEST" --ignore-not-found=true >/dev/null 2>&1 || true
  fi
  kubectl taint node "$NODE_NAME" taint-color:NoSchedule- >/dev/null 2>&1 || true
  kubectl taint node "$NODE_NAME" dedicated:NoSchedule- >/dev/null 2>&1 || true
  kubectl label node "$NODE_NAME" node-role.kubernetes.io/premium- >/dev/null 2>&1 || true
  kubectl label node "$NODE_NAME" demo- >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. DaemonSet
daemonsetReady=$(kubectl get daemonset -n dev -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo "0")
if [[ -n "$daemonsetReady" && "$daemonsetReady" -ge 1 ]]; then
  log_pass "The daemonset is deployed and ready."
else
  log_fail "The daemonset is not ready."
fi

# 2. Static Pod
if [[ -f "$STATIC_POD_SCRIPT" ]]; then
  bash "$STATIC_POD_SCRIPT" >/dev/null 2>&1 || true
  sleep 3
  staticPodReady=$(kubectl get pods -A -l app=static-nginx -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  if [[ "$staticPodReady" == "true" ]]; then
    log_pass "The static pod is deployed and ready."
  else
    log_fail "The static pod is not ready."
  fi
  bash "$STATIC_POD_SCRIPT" r >/dev/null 2>&1 || true
else
  log_fail "Static pod script not found at $STATIC_POD_SCRIPT"
fi

# 3. PriorityClass
prio_name=$(kubectl get deployments.apps -n dev nginx -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
if [[ -n "$prio_name" ]]; then
  log_pass "The deployment nginx has priorityClassName: $prio_name."
else
  log_fail "The deployment nginx does not have a priority class name configured."
fi

if kubectl get priorityclass nginx >/dev/null 2>&1; then
  log_pass "PriorityClass nginx exists."
else
  log_fail "PriorityClass nginx does not exist."
fi

# 4. Taints & Tolerations scenario
if [[ ! -f "$MANIFEST" ]]; then
  log_fail "Manifest $MANIFEST does not exist."
else
  # Setup node label and unmatched taint (blue)
  kubectl label node "$NODE_NAME" node-role.kubernetes.io/premium="true" --overwrite >/dev/null 2>&1
  kubectl taint node "$NODE_NAME" taint-color=blue:NoSchedule --overwrite >/dev/null 2>&1

  kubectl apply -f "$MANIFEST" >/dev/null 2>&1
  sleep 4

  phase=$(kubectl get pods -n default -l app=nginx-tainted -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [[ "$phase" == "Pending" ]]; then
    log_pass "Pod is Pending when node has blue taint (toleration is yellow)."
  else
    log_fail "Expected pod to be Pending with blue taint, got phase: '$phase'."
  fi

  kubectl delete -f "$MANIFEST" --ignore-not-found=true >/dev/null 2>&1

  # Apply matching taint (yellow)
  kubectl taint node "$NODE_NAME" taint-color=yellow:NoSchedule --overwrite >/dev/null 2>&1
  kubectl apply -f "$MANIFEST" >/dev/null 2>&1

  ready="false"
  for _ in {1..15}; do
    phase=$(kubectl get pods -n default -l app=nginx-tainted -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Running" ]]; then
      ready="true"
      break
    fi
    sleep 2
  done

  if [[ "$ready" == "true" ]]; then
    log_pass "Pod is Running after switching node taint to yellow."
  else
    log_fail "Pod failed to reach Running state with matching yellow toleration."
  fi

  # 5. NodeAffinity scenario
  kubectl delete -f "$MANIFEST" --ignore-not-found=true >/dev/null 2>&1

  kubectl label node "$NODE_NAME" node-role.kubernetes.io/premium- >/dev/null 2>&1 || true
  kubectl apply -f "$MANIFEST" >/dev/null 2>&1
  sleep 4

  phase_no_label=$(kubectl get pods -n default -l app=nginx-tainted -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [[ "$phase_no_label" == "Pending" ]]; then
    log_pass "Pod is Pending when node misses required nodeAffinity label."
  else
    log_fail "Expected pod to be Pending without affinity label, got phase: '$phase_no_label'."
  fi

  kubectl label node "$NODE_NAME" node-role.kubernetes.io/premium="true" --overwrite >/dev/null 2>&1

  ready_affinity="false"
  for _ in {1..15}; do
    phase=$(kubectl get pods -n default -l app=nginx-tainted -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Running" ]]; then
      ready_affinity="true"
      break
    fi
    sleep 2
  done

  if [[ "$ready_affinity" == "true" ]]; then
    log_pass "Pod is Running after re-applying nodeAffinity label."
  else
    log_fail "Pod failed to reach Running state after re-applying affinity label."
  fi

  kubectl delete -f "$MANIFEST" --ignore-not-found=true >/dev/null 2>&1
fi

write_result_file
