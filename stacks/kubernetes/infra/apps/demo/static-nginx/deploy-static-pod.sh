#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_NAME="static-pod-nginx.yaml"
SOURCE_MANIFEST="$SCRIPT_DIR/$MANIFEST_NAME"

# K3s supporte /var/lib/rancher/k3s/agent/pod-manifests (static pods kubelet)
# et /var/lib/rancher/k3s/server/manifests (addons/manifests control plane)
TARGET_DIRS=(
  "/var/lib/rancher/k3s/agent/pod-manifests"
  "/var/lib/rancher/k3s/server/manifests"
)

if [[ "${1:-}" == "r" ]]; then
  echo "Removing static pod manifest..."
  for dir in "${TARGET_DIRS[@]}"; do
    if [[ -f "$dir/$MANIFEST_NAME" ]]; then
      rm -f "$dir/$MANIFEST_NAME"
    fi
  done
else
  if [[ ! -f "$SOURCE_MANIFEST" ]]; then
    echo "Error: Source manifest $SOURCE_MANIFEST not found" >&2
    exit 1
  fi

  # Deploie en priorite dans le dossier pod-manifests s'il existe, sinon server/manifests
  DEPLOYED=false
  for dir in "${TARGET_DIRS[@]}"; do
    if [[ -d "$(dirname "$dir")" ]]; then
      mkdir -p "$dir"
      cp "$SOURCE_MANIFEST" "$dir/"
      echo "Deployed $MANIFEST_NAME to $dir/"
      DEPLOYED=true
      break
    fi
  done

  if [[ "$DEPLOYED" == "false" ]]; then
    # Fallback par defaut
    mkdir -p "/var/lib/rancher/k3s/server/manifests"
    cp "$SOURCE_MANIFEST" "/var/lib/rancher/k3s/server/manifests/"
    echo "Deployed $MANIFEST_NAME to /var/lib/rancher/k3s/server/manifests/"
  fi
fi
