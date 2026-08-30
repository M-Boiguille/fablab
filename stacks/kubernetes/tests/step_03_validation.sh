#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

NAMESPACE="dev"
DEPLOYMENT="nginx"
SERVICE="nginx-service"
RESULT_FILE="tests/step_03_result.txt"
LOG_FILE=$(mktemp)

PASS_COUNT=0
FAIL_COUNT=0

# Prepare result directory/file
mkdir -p "$(dirname "$RESULT_FILE")"

function log_pass {
  local message="$1"

  echo -e "${GREEN}PASS${NC} | $message"
  echo "PASS | $message" >>"$LOG_FILE"
  PASS_COUNT=$((PASS_COUNT + 1))
}

function log_fail {
  local message="$1"

  echo -e "${RED}FAIL${NC} | $message"
  echo "FAIL | $message" >>"$LOG_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

function check {
  local description="$1"
  local command="$2"
  local expected="$3"

  result=$(eval "$command" 2>/dev/null)

  if [ "$result" == "$expected" ]; then
    log_pass "$description"
  else
    log_fail "$description (expected '$expected', got '$result')"
  fi
}

echo "========================================="
echo "--   STEP 03 - VALIDATION SCRIPT           "
echo "========================================="
echo ""

echo "# Namespace: $NAMESPACE"
echo "# Deployment: $DEPLOYMENT"
echo "# Service: $SERVICE"
echo ""

# ============================================================
# 1. DEPLOYMENT
# ============================================================

echo "--- Testing Deployment ---"

check \
  "Deployment '$DEPLOYMENT' exists in namespace '$NAMESPACE'" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o name" \
  "deployment.apps/$DEPLOYMENT"

check \
  "Deployment has 3 desired replicas" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.spec.replicas}'" \
  "3"

check \
  "Deployment has 3 ready replicas" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.status.readyReplicas}'" \
  "3"

check \
  "Deployment has RollingUpdate strategy" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.spec.strategy.type}'" \
  "RollingUpdate"

check \
  "Deployment has maxUnavailable=1" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}'" \
  "1"

check \
  "Deployment has maxSurge=1" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}'" \
  "1"

check \
  "Deployment has imagePullPolicy IfNotPresent" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}'" \
  "IfNotPresent"

# ============================================================
# 2. SERVICE
# ============================================================

echo ""
echo "--- Testing Service ---"

check \
  "Service '$SERVICE' exists in namespace '$NAMESPACE'" \
  "kubectl get service '$SERVICE' -n '$NAMESPACE' -o name" \
  "service/$SERVICE"

check \
  "Service is of type ClusterIP" \
  "kubectl get service '$SERVICE' -n '$NAMESPACE' -o jsonpath='{.spec.type}'" \
  "ClusterIP"

check \
  "Service selector matches Deployment label" \
  "kubectl get service '$SERVICE' -n '$NAMESPACE' -o jsonpath='{.spec.selector.app}'" \
  "nginx"

check \
  "Service targetPort is 80" \
  "kubectl get service '$SERVICE' -n '$NAMESPACE' -o jsonpath='{.spec.ports[0].targetPort}'" \
  "80"

# ============================================================
# 3. ENDPOINTS
# ============================================================

echo ""
echo "--- Testing Service Endpoints ---"

ENDPOINT_COUNT=$(kubectl get endpoints "$SERVICE" \
  -n "$NAMESPACE" \
  -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null |
  wc -w)

if [ "$ENDPOINT_COUNT" -eq 3 ]; then
  log_pass "Service has 3 populated endpoints"
else
  log_fail "Service should have 3 populated endpoints (got '$ENDPOINT_COUNT')"
fi

# ============================================================
# 4. FINAL RESULT
# ============================================================

echo ""
echo "========================================="
echo "--   VALIDATION COMPLETE                   "
echo "========================================="
echo ""

echo "# PASS: $PASS_COUNT"
echo "# FAIL: $FAIL_COUNT"

{
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
  echo "--- Summary ---"
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "Step 03 validation successful: $PASS_COUNT passed, $FAIL_COUNT failed."
    echo "All checks passed for Deployment $DEPLOYMENT, Service $SERVICE, and 3 endpoints in namespace $NAMESPACE."
  else
    echo "Step 03 validation failed: $PASS_COUNT passed, $FAIL_COUNT failed."
  fi
  cat "$LOG_FILE"
  echo "# PASS: $PASS_COUNT"
  echo "# FAIL: $FAIL_COUNT"
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "# PASS | Step 03 validation successful"
  else
    echo "# FAIL | Step 03 validation failed"
  fi
} > "$RESULT_FILE"

rm -f "$LOG_FILE"

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}OVERALL: PASS${NC}"
  exit 0
else
  echo -e "${RED}OVERALL: FAIL${NC}"
  exit 1
fi
