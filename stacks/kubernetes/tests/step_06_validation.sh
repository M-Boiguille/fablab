#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$SCRIPT_DIR/step_06_result.txt"

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

write_result_file() {
  local status="PASS"
  local status_word="successful"
  if (( FAIL_COUNT > 0 )); then
    status="FAIL"
    status_word="failed"
  fi

  {
    echo "$status"
    echo "--- Summary ---"
    echo "Step 06 validation: $PASS_COUNT passed, $FAIL_COUNT failed"
    for entry in "${LOG_ENTRIES[@]}"; do
      echo "$entry"
    done
    echo "# PASS: $PASS_COUNT"
    echo "# FAIL: $FAIL_COUNT"
    echo "# $status | Step 06 validation $status_word"
  } > "$RESULT_FILE"
}

cleanup() {
  echo "🧹 Cleaning up test pods..." >&2
  kubectl delete pod -n staging -l app=switch-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete pod -n dev -l app=canary-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

exit_handler() {
  cleanup
  write_result_file
}
trap exit_handler EXIT

command -v kubectl >/dev/null 2>&1 || {
  log_fail "kubectl is required but not installed"
  exit 1
}

# ----------------------------------------------------------------------
# Blue/Green validation in staging
# ----------------------------------------------------------------------

NAMESPACE_STAGING="staging"
SERVICE_STAGING="nginx-service"
BLUE_VERSION="1.30.4"
GREEN_VERSION="1.31.5"
TRACK_BLUE="blue"
TRACK_GREEN="green"
TEST_LABEL_STAGING="app=switch-test"

run_curl_version_staging() {
  local name="$1"
  local output
  output=$(kubectl run "$name" -n "$NAMESPACE_STAGING" \
    --image=curlimages/curl \
    --restart=Never \
    --labels="$TEST_LABEL_STAGING" \
    --attach \
    --command -- /bin/sh -c 'curl -sS --connect-timeout 0.2 --max-time 1 http://nginx-service:8080/version' 2>/dev/null || true)
  echo "$output" | tail -n1 | tr -d '\n'
}

echo "--- Blue/Green deployment validation (staging) ---"

current_track=$(kubectl get service -n "$NAMESPACE_STAGING" "$SERVICE_STAGING" -o jsonpath='{.spec.selector.track}' 2>/dev/null || true)

if [[ "$current_track" == "$TRACK_BLUE" ]]; then
  current_version="$BLUE_VERSION"
  target_track="$TRACK_GREEN"
  target_version="$GREEN_VERSION"
  log_pass "Current track is blue; target is green"
elif [[ "$current_track" == "$TRACK_GREEN" ]]; then
  current_version="$GREEN_VERSION"
  target_track="$TRACK_BLUE"
  target_version="$BLUE_VERSION"
  log_pass "Current track is green; target is blue"
else
  current_version=""
  target_track=""
  target_version=""
  log_fail "Current track must be blue or green (got '$current_track')"
fi

if [[ -n "$target_track" ]]; then
  before_version=$(run_curl_version_staging switch-test-before)
  if [[ "$before_version" == "$current_version" ]]; then
    log_pass "Service returns current version $before_version before switch"
  else
    log_fail "Service version before switch is '$before_version' (expected '$current_version')"
  fi

  if kubectl patch -n "$NAMESPACE_STAGING" service "$SERVICE_STAGING" \
    --type='merge' \
    -p "{\"spec\":{\"selector\":{\"track\":\"$target_track\"}}}" >/dev/null 2>&1; then
    log_pass "Service selector patched to $target_track"
  else
    log_fail "Failed to patch service selector to $target_track"
  fi

  actual_track=""
  for _ in $(seq 1 30); do
    actual_track=$(kubectl get service -n "$NAMESPACE_STAGING" "$SERVICE_STAGING" -o jsonpath='{.spec.selector.track}' 2>/dev/null || true)
    [[ "$actual_track" == "$target_track" ]] && break
    sleep 1
  done

  if [[ "$actual_track" == "$target_track" ]]; then
    log_pass "Service selector is now $target_track"
  else
    log_fail "Service selector did not update to $target_track (got '$actual_track')"
  fi

  after_version=$(run_curl_version_staging switch-test-after)
  if [[ "$after_version" == "$target_version" ]]; then
    log_pass "Service returns target version $after_version after switch"
  else
    log_fail "Service version after switch is '$after_version' (expected '$target_version')"
  fi
fi

# ----------------------------------------------------------------------
# Canary validation in dev
# ----------------------------------------------------------------------

NAMESPACE_DEV="dev"
SERVICE_DEV="nginx-service"
STABLE_DEPLOY="nginx"
CANARY_DEPLOY="nginx-canary"
VERSION_STABLE="1.30.4"
VERSION_CANARY="1.31.5"
POD_LABEL="app=canary-test"
POD_NAME="canary-test-pod"
NB_REQ=1000

scale_deployment() {
  local deployment="$1"
  local replicas="$2"

  if kubectl scale deployment -n "$NAMESPACE_DEV" "$deployment" --replicas "$replicas" >/dev/null 2>&1; then
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
    current_replicas=$(kubectl get deployment -n "$NAMESPACE_DEV" "$deployment" -o jsonpath='{.status.replicas}' 2>/dev/null || true)
    ready_loop=$(kubectl get deployment -n "$NAMESPACE_DEV" "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

    if [[ "$replicas" -eq 0 ]]; then
      # For zero replicas, check status.replicas only. readyReplicas may be
      # empty or non-zero while pods are terminating, so it is not reliable here.
      if [[ -z "$current_replicas" || "$current_replicas" == "0" ]]; then
        ready="0"
        break
      fi
    else
      # For >0 replicas, require readyReplicas to match the desired count.
      if [[ "$ready_loop" == "$replicas" ]]; then
        ready="$ready_loop"
        break
      fi
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  if [[ "$replicas" -eq 0 ]]; then
    if [[ "$ready" == "0" ]]; then
      log_pass "$deployment scaled to 0 replicas"
    else
      log_fail "$deployment did not scale to 0 replicas (status.replicas='$current_replicas')"
      return 1
    fi
  else
    if [[ "$ready" == "$replicas" ]]; then
      log_pass "$deployment has $replicas ready replicas"
    else
      log_fail "$deployment does not have $replicas ready replicas (got '$ready')"
      return 1
    fi
  fi
}

run_canary_test() {
  local output
  output=$(kubectl run "$POD_NAME" -n "$NAMESPACE_DEV" \
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

  local stable_count canary_count errors_count
  stable_count=$(awk -F': ' '/^stable:/ {split($2,a," - "); print a[1]}' <<<"$out")
  canary_count=$(awk -F': ' '/^canary:/ {split($2,a," - "); print a[1]}' <<<"$out")
  errors_count=$(awk -F': ' '/^errors:/ {print $2}' <<<"$out")

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

echo "--- Canary deployment validation (dev) ---"

check_palier 3 0
check_palier 3 1
check_palier 3 2
check_palier 3 3
check_palier 3 0

# The EXIT trap writes the result file and cleans up test pods.
exit 0
