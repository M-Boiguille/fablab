#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_OVERLAY="$SCRIPT_DIR/../infra/"

fail() {
  echo "❌ $1" >&2
  exit 1
}

command -v kubectl >/dev/null 2>&1 || fail "kubectl is required but not installed"

cleanup() {
  echo "🧹 Cleaning up infrastructure..."
  kubectl delete -k "$INFRA_OVERLAY" || true
}
trap cleanup EXIT

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
echo "🔧 Validating kustomize build..."
kubectl kustomize "$INFRA_OVERLAY" || fail "kustomize build failed"

# 2. Deploy infrastructure
echo "🚀 Deploying infrastructure from overlay tests..."
kubectl apply -k "$INFRA_OVERLAY"

# 3. Wait for namespaces to become Active
for ns in dev staging prod tools; do
  echo "⏳ Waiting for namespace $ns..."
  wait_for_namespace "$ns" 60 || fail "Namespace $ns did not become Active"
done

# 4. Verify ResourceQuota and LimitRange presence
echo "🔎 Checking ResourceQuota and LimitRange in each namespace..."
for ns in dev staging prod tools; do
  kubectl get resourcequota -n "$ns" >/dev/null || fail "No ResourceQuota found in $ns"
  kubectl get limitrange -n "$ns" >/dev/null || fail "No LimitRange found in $ns"
done

# 5. Test LimitRange default values
echo "🧪 Testing LimitRange default values..."
kubectl apply -f - <<'EOF'
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
echo "✅ Default requests correctly applied (CPU: $CPU_REQUEST, memory: $MEM_REQUEST)"

kubectl delete pod test-limitrange-default -n dev --ignore-not-found=true

# 6. Test LimitRange max rejection
echo "🧪 Testing LimitRange max rejection..."
if kubectl apply -f - <<'EOF'
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
  echo "✅ Pod exceeding LimitRange max was correctly rejected"
fi

# 7. Test ResourceQuota pod count limit
echo "🧪 Testing ResourceQuota pod count limit..."
for i in $(seq 1 5); do
  kubectl apply -f - <<EOF
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

if kubectl apply -f - <<'EOF'
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
  echo "✅ 6th pod was correctly rejected due to ResourceQuota pods limit"
fi

# Cleanup test pods manually (trap cleanup will also remove the whole overlay)
kubectl delete pod quota-test-{1..5} -n dev --ignore-not-found=true

echo "✅ Step 05 validation passed"
exit 0
