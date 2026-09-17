#!/bin/bash

set -euo pipefail

NAMESPACE="staging"
SERVICE="nginx-service"
VERSION_BLUE="1.30.4"
VERSION_GREEN="1.31.5"
TRACK_BLUE="blue"
TRACK_GREEN="green"

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
  echo "Step 06 Blue/Green switch validation: $PASS_COUNT passed, $FAIL_COUNT failed"
  for entry in "${LOG_ENTRIES[@]}"; do
    echo "$entry"
  done
  echo "# PASS: $PASS_COUNT"
  echo "# FAIL: $FAIL_COUNT"
  if (( FAIL_COUNT == 0 )); then
    echo "# PASS | Step 06 Blue/Green switch validation successful"
  else
    echo "# FAIL | Step 06 Blue/Green switch validation failed"
  fi
}

cleanup() {
  kubectl delete pod -n "$NAMESPACE" -l app=switch-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_curl_version() {
  local name="$1"
  local output
  output=$(kubectl run "$name" -n "$NAMESPACE" \
    --image=curlimages/curl \
    --restart=Never \
    --labels=app=switch-test \
    --attach \
    --command -- /bin/sh -c 'curl -sS --connect-timeout 0.2 --max-time 1 http://nginx-service:8080/version' 2>/dev/null || true)
  echo "$output" | tail -n1 | tr -d '\n'
}

command -v kubectl >/dev/null 2>&1 || {
  log_fail "kubectl is required but not installed"
  summary
  exit 1
}

echo "--- Testing current service track ---"
current_track=$(kubectl get service -n "$NAMESPACE" "$SERVICE" -o jsonpath='{.spec.selector.track}' 2>/dev/null || true)
if [[ "$current_track" == "$TRACK_BLUE" ]]; then
  current_version="$VERSION_BLUE"
  target_track="$TRACK_GREEN"
  target_version="$VERSION_GREEN"
  log_pass "Current track is blue, switch to green"
elif [[ "$current_track" == "$TRACK_GREEN" ]]; then
  current_version="$VERSION_GREEN"
  target_track="$TRACK_BLUE"
  target_version="$VERSION_BLUE"
  log_pass "Current track is green, switch to blue"
else
  current_version=""
  target_track=""
  target_version=""
  log_fail "Current track must be blue or green (got '$current_track')"
fi

if [[ -n "$target_track" ]]; then
  echo "--- Testing version before switch ---"
  before_version=$(run_curl_version switch-test-before)
  if [[ "$before_version" == "$current_version" ]]; then
    log_pass "Service returns current version $before_version before switch"
  else
    log_fail "Service version before switch is '$before_version' (expected '$current_version')"
  fi

  echo "--- Switching service selector ---"
  if kubectl patch -n "$NAMESPACE" service "$SERVICE" \
    --type='merge' \
    -p "{\"spec\":{\"selector\":{\"track\":\"$target_track\"}}}" >/dev/null 2>&1; then
    log_pass "Service selector patched to $target_track"
  else
    log_fail "Failed to patch service selector to $target_track"
  fi

  echo "--- Waiting for selector update ---"
  actual_track=""
  for _ in $(seq 1 30); do
    actual_track=$(kubectl get service -n "$NAMESPACE" "$SERVICE" -o jsonpath='{.spec.selector.track}' 2>/dev/null || true)
    [[ "$actual_track" == "$target_track" ]] && break
    sleep 1
  done
  if [[ "$actual_track" == "$target_track" ]]; then
    log_pass "Service selector is now $target_track"
  else
    log_fail "Service selector did not update to $target_track (got '$actual_track')"
  fi

  echo "--- Testing version after switch ---"
  after_version=$(run_curl_version switch-test-after)
  if [[ "$after_version" == "$target_version" ]]; then
    log_pass "Service returns target version $after_version after switch"
  else
    log_fail "Service version after switch is '$after_version' (expected '$target_version')"
  fi
fi

summary
if (( FAIL_COUNT > 0 )); then
  exit 1
else
  exit 0
fi
