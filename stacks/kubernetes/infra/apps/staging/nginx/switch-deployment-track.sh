#!/bin/bash

set -euo pipefail

NAMESPACE="staging"
SERVICE="nginx-service"
POD_LABEL="app=test"
POD_NAME="test-curl"

cleanup() {
  echo ""
  echo "Cleaning up test pod..."
  kubectl delete pod -n "$NAMESPACE" -l "$POD_LABEL" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl delete pod -n "$NAMESPACE" -l "$POD_LABEL" --ignore-not-found --wait=true >/dev/null 2>&1 || true

current_track=$(kubectl get service -n "$NAMESPACE" "$SERVICE" \
  -o jsonpath='{.spec.selector.track}')

if [[ "$current_track" == "blue" ]]; then
  track="green"
elif [[ "$current_track" == "green" ]]; then
  track="blue"
else
  echo "Error: $SERVICE selector.track is '$current_track' (expected 'blue' or 'green')." >&2
  exit 1
fi

echo "Current track: $current_track -> switching to: $track"

kubectl run "$POD_NAME" -n "$NAMESPACE" \
  --image=curlimages/curl \
  --restart=Never \
  --labels="$POD_LABEL" \
  -- sh -c '
      while true; do
        printf "[%s] " "$(date "+%H:%M:%S.%3N")"
        curl -sS --connect-timeout 0.2 --max-time 1 \
          http://nginx-service:8080/version 2>&1
        echo
        sleep 0.1
      done
'

echo -n "Waiting for $POD_NAME to be ready..."

until kubectl wait --for=condition=Ready "pod/$POD_NAME" -n "$NAMESPACE" \
  --timeout=1s >/dev/null 2>&1; do
  sleep 1
  echo -ne "."
done

echo ""
echo "$POD_NAME is ready."

# Laisse le temps à curl de produire plusieurs cycles
sleep 1

echo "Switching service to: $track"

kubectl patch -n "$NAMESPACE" service "$SERVICE" \
  --type='merge' \
  -p "{\"spec\":{\"selector\":{\"track\":\"$track\"}}}"

until [[ "$(kubectl get service -n "$NAMESPACE" "$SERVICE" \
  -o jsonpath='{.spec.selector.track}')" == "$track" ]]; do
  sleep 1
done

echo "$SERVICE is now pointing to $track."

# Laisse le temps de voir le changement de réponse après le switch
sleep 1

echo "===== Logs from $POD_NAME ====="
kubectl logs -n "$NAMESPACE" -l "$POD_LABEL" --prefix --tail=-1
