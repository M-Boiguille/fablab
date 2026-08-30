#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

NAMESPACE="dev"
DEPLOYMENT="nginx"
SERVICE="nginx-service"
RESULT_FILE="tests/step_03_result.txt"

PASS_COUNT=0
FAIL_COUNT=0

# Prepare result directory/file
mkdir -p "$(dirname "$RESULT_FILE")"
: >"$RESULT_FILE"

function log_pass {
  local message="$1"

  echo -e "${GREEN}PASS${NC} | $message"
  echo "PASS | $message" >>"$RESULT_FILE"
  PASS_COUNT=$((PASS_COUNT + 1))
}

function log_fail {
  local message="$1"

  echo -e "${RED}FAIL${NC} | $message"
  echo "FAIL | $message" >>"$RESULT_FILE"
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
echo "   STEP 03 - VALIDATION SCRIPT           "
echo "========================================="
echo ""

echo "Namespace: $NAMESPACE"
echo "Deployment: $DEPLOYMENT"
echo "Service: $SERVICE"
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
  "Deployment has maxSurge=2" \
  "kubectl get deployment '$DEPLOYMENT' -n '$NAMESPACE' -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}'" \
  "2"

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
echo "   VALIDATION COMPLETE                   "
echo "========================================="
echo ""

echo "PASS: $PASS_COUNT"
echo "FAIL: $FAIL_COUNT"

echo ""
echo "Result written to: $RESULT_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS | Step 03 validation successful" >>"$RESULT_FILE"
  echo -e "${GREEN}OVERALL: PASS${NC}"
  exit 0
else
  echo "FAIL | Step 03 validation failed" >>"$RESULT_FILE"
  echo -e "${RED}OVERALL: FAIL${NC}"
  exit 1
fi
