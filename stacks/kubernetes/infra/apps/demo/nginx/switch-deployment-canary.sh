#!/bin/bash

set -euo pipefail

NAMESPACE="dev"
SERVICE="nginx-service"
STABLE_DEPLOY="nginx"
CANARY_DEPLOY="nginx-canary"
VERSION_STABLE="1.30.4"
VERSION_CANARY="1.31.5"
POD_LABEL="app=canary-test"
POD_NAME="canary-test-pod"
NB_REQ=1000

PASS_COUNT=0
FAIL_COUNT=0
LOG_ENTRIES=()

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

summary() {
  local status="PASS"
  if (( FAIL_COUNT > 0 )); then
    status="FAIL"
  fi

  echo "$status"
  echo "--- Summary ---"
  echo "Step 06 Canary switch validation: $PASS_COUNT passed, $FAIL_COUNT failed"
  for entry in "${LOG_ENTRIES[@]}"; do
    echo "$entry"
  done
  echo "# PASS: $PASS_COUNT"
  echo "# FAIL: $FAIL_COUNT"
  if (( FAIL_COUNT == 0 )); then
    echo "# PASS | Step 06 Canary switch validation successful"
  else
    echo "# FAIL | Step 06 Canary switch validation failed"
  fi
}

cleanup() {
  kubectl delete pod -n "$NAMESPACE" -l "$POD_LABEL" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v kubectl >/dev/null 2>&1 || {
  log_fail "kubectl is required but not installed"
  summary
  exit 1
}

scale_deployment() {
  local deployment="$1"
  local replicas="$2"

  if kubectl scale deployment -n "$NAMESPACE" "$deployment" --replicas "$replicas" >/dev/null 2>&1; then
    log_pass "Scaled $deployment to $replicas replicas"
  else
    log_fail "Failed to scale $deployment to $replicas replicas"
    return 1
  fi

  local timeout=60
  local interval=2
  local elapsed=0
  local ready=""
  local current_replicas=""
  local ready_loop=""

  while [[ $elapsed -lt $timeout ]]; do
    current_replicas=$(kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.status.replicas}' 2>/dev/null || true)
    ready_loop=$(kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

    if [[ "$replicas" -eq 0 ]]; then
      # When scaling to zero we only require status.replicas to become 0 (or missing).
      # readyReplicas may briefly remain non-zero while pods are terminating, so it is not
      # a reliable indicator for a zero-replica Deployment.
      if [[ -z "$current_replicas" || "$current_replicas" == "0" ]]; then
        ready="0"
        break
      fi
    else
      if [[ "$ready_loop" == "$replicas" ]]; then
        ready="$ready_loop"
        break
      fi
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  if [[ "$ready" == "$replicas" ]]; then
    log_pass "$deployment has $replicas ready replicas"
  else
    log_fail "$deployment does not have $replicas ready replicas (got '$ready')"
    return 1
  fi
}

run_canary_test() {
  local output
  output=$(kubectl run "$POD_NAME" -n "$NAMESPACE" \
    --image=curlimages/curl \
    --restart=Never \
    --labels="$POD_LABEL" \
    --rm \
    --attach \
    --command -- /bin/sh -c '
        i=0
        stable=0
        canary=0
        errors=0
        while [ "$i" -lt '"$NB_REQ"' ]; do
          version="$(curl -sS --connect-timeout 0.2 --max-time 1 http://nginx-service:8080/version 2>&1)"
          if [ "$version" = "'"$VERSION_CANARY"'" ]; then
            canary=$((canary + 1))
          elif [ "$version" = "'"$VERSION_STABLE"'" ]; then
            stable=$((stable + 1))
          else
            errors=$((errors + 1))
          fi
          i=$((i + 1))
        done
        echo "stable: $stable - $(($stable * 100 / '"$NB_REQ"'))%"
        echo "canary: $canary - $(($canary * 100 / '"$NB_REQ"'))%"
        echo "errors: $errors"
    ' 2>/dev/null || true)
  echo "$output"
}

check_palier() {
  local stable_replicas="$1"
  local canary_replicas="$2"

  echo "--- Testing palier stable=$stable_replicas canary=$canary_replicas ---"

  if ! scale_deployment "$STABLE_DEPLOY" "$stable_replicas"; then
    return 1
  fi

  if ! scale_deployment "$CANARY_DEPLOY" "$canary_replicas"; then
    return 1
  fi

  local out
  out=$(run_canary_test)

  local stable_count
  local canary_count
  local errors_count
  stable_count=$(echo "$out" | grep '^stable:' | awk -F': ' '{print $2}' | awk -F' - ' '{print $1}')
  canary_count=$(echo "$out" | grep '^canary:' | awk -F': ' '{print $2}' | awk -F' - ' '{print $1}')
  errors_count=$(echo "$out" | grep '^errors:' | awk -F': ' '{print $2}')

  if [[ -z "$stable_count" || -z "$canary_count" || -z "$errors_count" ]]; then
    log_fail "Could not parse canary test output"
    return 1
  fi

  if [[ "$errors_count" == "0" ]]; then
    log_pass "Canary test completed without errors"
  else
    log_fail "Canary test encountered $errors_count errors"
    return 1
  fi

  if [[ "$canary_replicas" -eq 0 ]]; then
    if [[ "$canary_count" == "0" ]]; then
      log_pass "No canary traffic observed when canary replicas=0"
    else
      log_fail "Expected no canary traffic when canary replicas=0, got $canary_count"
      return 1
    fi
  else
    if [[ "$canary_count" -gt 0 ]]; then
      log_pass "Canary traffic observed: $canary_count requests"
    else
      log_fail "Expected canary traffic when canary replicas=$canary_replicas, got 0"
      return 1
    fi
  fi

  if [[ "$stable_count" -gt 0 ]]; then
    log_pass "Stable traffic observed: $stable_count requests"
  else
    log_fail "Expected stable traffic, got 0"
    return 1
  fi
}

check_palier 3 0
check_palier 3 1
check_palier 3 2
check_palier 3 3
check_palier 3 0

summary
if (( FAIL_COUNT > 0 )); then
  exit 1
else
  exit 0
fi
