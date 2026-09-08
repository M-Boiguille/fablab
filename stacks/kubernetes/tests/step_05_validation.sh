#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_OVERLAY="$SCRIPT_DIR/../infra/"
RESULT_FILE="$SCRIPT_DIR/step_05_result.txt"

PASS_COUNT=0
FAIL_COUNT=0
LOG_ENTRIES=()

log_pass() {
  local msg="$1"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  LOG_ENTRIES+=("[$ts] PASS | $msg")
  PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
  local msg="$1"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  LOG_ENTRIES+=("[$ts] FAIL | $msg")
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

fail() {
  local msg="$1"
  log_fail "$msg"
  echo "❌ $msg" >&2
  exit 1
}

write_result_file() {
  local status="PASS"
  local status_word="successful"
  if (( FAIL_COUNT > 0 )); then
    status="FAIL"
    status_word="failed"
  fi

  local now
  now=$(date '+%Y-%m-%d %H:%M:%S')

  {
    echo "$status"
    echo "--- Summary ---"
    echo "[$now] Step 05 validation: $PASS_COUNT passed, $FAIL_COUNT failed"
    for entry in "${LOG_ENTRIES[@]}"; do
      echo "$entry"
    done
    echo "# PASS: $PASS_COUNT"
    echo "# FAIL: $FAIL_COUNT"
    echo "[$now] # $status | Step 05 validation $status_word"
  } > "$RESULT_FILE"
}

cleanup() {
  echo "🧹 Cleaning up infrastructure..." >&2
  kubectl delete -k "$INFRA_OVERLAY" >/dev/null 2>&1 || true
}

exit_handler() {
  cleanup
  write_result_file
}
trap exit_handler EXIT

command -v kubectl >/dev/null 2>&1 || fail "kubectl is required but not installed"

wait_for_namespace() {
  local ns="$1"
  local timeout="${2:-60}"
  local interval=2
  local elapsed=0

  while [[ $elapsed -lt $timeout ]]; do
    local phase
    phase=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Active" ]]; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  return 1
}

wait_for_pod_field() {
  local pod="$1"
  local ns="$2"
  local jsonpath="$3"
  local timeout="${4:-30}"
  local interval=2
  local elapsed=0

  while [[ $elapsed -lt $timeout ]]; do
    local value
    value=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="$jsonpath" 2>/dev/null || true)
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  return 1
}

# 1. Validate kustomize build
echo "🔧 Validating kustomize build..." >&2
kubectl kustomize "$INFRA_OVERLAY" >/dev/null || fail "kustomize build failed"
log_pass "kustomize build successful"

# 2. Deploy infrastructure
echo "🚀 Deploying infrastructure..." >&2
kubectl apply -k "$INFRA_OVERLAY" >/dev/null || fail "infrastructure deployment failed"
log_pass "Infrastructure deployed"

# 3. Wait for namespaces to become Active
for ns in dev staging prod tools; do
  echo "⏳ Waiting for namespace $ns..." >&2
  wait_for_namespace "$ns" 60 || fail "Namespace $ns did not become Active"
done
log_pass "All namespaces are Active"

# 4. Verify ResourceQuota and LimitRange presence
echo "🔎 Checking ResourceQuota and LimitRange in each namespace..." >&2
for ns in dev staging prod tools; do
  kubectl get resourcequota -n "$ns" >/dev/null || fail "No ResourceQuota found in $ns"
  kubectl get limitrange -n "$ns" >/dev/null || fail "No LimitRange found in $ns"
done
log_pass "ResourceQuota and LimitRange present in all namespaces"

# 5. Test LimitRange default values
echo "🧪 Testing LimitRange default values..." >&2
kubectl apply -f - >/dev/null <<'EOF' || fail "failed to create test-limitrange-default pod"
apiVersion: v1
kind: Pod
metadata:
  name: test-limitrange-default
  namespace: dev
spec:
  containers:
  - name: nginx
    image: nginx:alpine
EOF

CPU_REQUEST=$(wait_for_pod_field test-limitrange-default dev '{.spec.containers[0].resources.requests.cpu}' 30 || true)
MEM_REQUEST=$(wait_for_pod_field test-limitrange-default dev '{.spec.containers[0].resources.requests.memory}' 30 || true)

if [[ -z "$CPU_REQUEST" || -z "$MEM_REQUEST" ]]; then
  fail "Could not retrieve default requests from test-limitrange-default pod"
fi

[[ "$CPU_REQUEST" == "50m" ]] || fail "Expected default CPU request 50m, got '$CPU_REQUEST'"
[[ "$MEM_REQUEST" == "6Mi" ]] || fail "Expected default memory request 6Mi, got '$MEM_REQUEST'"
log_pass "LimitRange default values applied"

kubectl delete pod test-limitrange-default -n dev --ignore-not-found=true >/dev/null 2>&1 || true

# 6. Test LimitRange max rejection
echo "🧪 Testing LimitRange max rejection..." >&2
if kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-limitrange-max
  namespace: dev
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        cpu: "1"
        memory: "100Mi"
      limits:
        cpu: "1"
        memory: "100Mi"
EOF
then
  fail "Pod exceeding LimitRange max should have been rejected"
else
  log_pass "LimitRange max rejection enforced"
fi

# 7. Test ResourceQuota pod count limit
echo "🧪 Testing ResourceQuota pod count limit..." >&2
for i in $(seq 1 5); do
  kubectl apply -f - >/dev/null <<EOF || fail "failed to create quota-test-$i pod"
apiVersion: v1
kind: Pod
metadata:
  name: quota-test-$i
  namespace: dev
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        cpu: "10m"
        memory: "4Mi"
      limits:
        cpu: "10m"
        memory: "4Mi"
EOF
done

if kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: quota-test-6
  namespace: dev
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        cpu: "10m"
        memory: "4Mi"
      limits:
        cpu: "10m"
        memory: "4Mi"
EOF
then
  fail "6th pod should have been rejected due to ResourceQuota pods limit"
else
  log_pass "ResourceQuota pod count limit enforced"
fi

# Cleanup test pods manually (trap cleanup will also remove the whole overlay)
kubectl delete pod quota-test-{1..5} -n dev --ignore-not-found=true >/dev/null 2>&1 || true

# The result file is written by the EXIT trap
exit 0
