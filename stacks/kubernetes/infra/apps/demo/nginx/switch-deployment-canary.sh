#!/bin/bash

set -euo pipefail

SRC_NS="tools"
TARGET_NS="dev"
SERVICE="nginx-service"
POD_LABEL="app=test"
POD_NAME="test-curl"
CANARY="1.31.5"
STABLE="1.30.4"
NB_REQ=1000

cleanup() {
  echo ""
  echo "Cleaning up test pod..."
  kubectl delete pod -n "$SRC_NS" -l "$POD_LABEL" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

test_requests() {
  kubectl delete pod -n "$SRC_NS" -l "$POD_LABEL" --ignore-not-found --wait=true >/dev/null 2>&1 || true

  kubectl run "$POD_NAME" -n "$SRC_NS" \
    --image=curlimages/curl \
    --restart=Never \
    --labels="$POD_LABEL" \
    --env="CANARY=$CANARY" \
    --env="STABLE=$STABLE" \
    --env="NB_REQ=$NB_REQ" \
    -- sh -c '
        i=0
        stable=0
        canary=0
        errors=0

        while [ "$i" -lt "$NB_REQ" ]; do
          version="$(curl -sS --connect-timeout 0.2 --max-time 1 \
            http://nginx-service.dev.svc.cluster.local:8080/version 2>&1)"

          if [ "$version" = "$CANARY" ]; then
            canary=$((canary + 1))
          elif [ "$version" = "$STABLE" ]; then
            stable=$((stable + 1))
          else
            errors=$((errors + 1))
          fi

          i=$((i + 1))
        done

        echo "stable: $stable - $(($stable * 100 /$NB_REQ))%"
        echo "canary: $canary - $(($canary * 100 /$NB_REQ))%"
        echo "errors: $errors"
        '
  kubectl wait \
    --for=jsonpath='{.status.phase}'=Succeeded \
    pod/"$POD_NAME" \
    -n "$SRC_NS" \
    --timeout=180s

  echo "===== Logs from $POD_NAME ====="
  kubectl logs -n "$SRC_NS" -l "$POD_LABEL" --tail=10
}

wait_for_replicas() {
  local deployment="$1"
  local replicas="$2"

  echo "====> $deployment - $replicas"
  if [ "$replicas" -eq 0 ]; then
    kubectl wait \
      --for=jsonpath='{.spec.replicas}'=0 \
      "deployment/$deployment" \
      -n "$TARGET_NS" \
      --timeout=60s
  else
    kubectl wait \
      --for=jsonpath="{.status.readyReplicas}=$replicas" \
      "deployment/$deployment" \
      -n "$TARGET_NS" \
      --timeout=60s
  fi
}

rescale() {
  kubectl scale deployment -n "$TARGET_NS" -l track=stable --replicas "$1"
  kubectl scale deployment -n "$TARGET_NS" -l track=canary --replicas "$2"
  echo "Scale deployment -> stable $1"
  wait_for_replicas nginx "$1"
  wait_for_replicas nginx-canary "$2"
  kubectl get deployment -n dev
  test_requests
}

rescale 3 0
rescale 3 1
rescale 3 2
rescale 3 3
rescale 3 0
