#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

echo "📁 Projet : $ROOT"

# Vérification
if [[ ! -d "$ROOT/infra/apps/demo" ]]; then
  echo "❌ infra/apps/demo introuvable"
  exit 1
fi

if [[ ! -d "$ROOT/infra/overlays/tests" ]]; then
  echo "❌ infra/overlays/tests introuvable"
  exit 1
fi

# ─────────────────────────────────────────────
# 1. Créer la base Kustomize de demo
# ─────────────────────────────────────────────

cat >"$ROOT/infra/apps/demo/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - nginx/configmap-nginx.yaml
  - nginx/deployment-nginx.yaml
  - nginx/service-nginx.yaml

  - grafana/configmap-grafana.yaml
  - grafana/deployment-grafana.yaml
  - grafana/ingress-grafana.yaml
  - grafana/service-grafana.yaml

  - prometheus/config-configmap-prometheus.yaml
  - prometheus/rules-configmap-prometheus.yaml
  - prometheus/deployment-prometheus.yaml
  - prometheus/ingress.yaml
  - prometheus/service-prometheus.yaml
EOF

echo "✅ infra/apps/demo/kustomization.yaml créé"

# ─────────────────────────────────────────────
# 2. Sauvegarder l'ancien overlay
# ─────────────────────────────────────────────

OVERLAY="$ROOT/infra/overlays/tests/kustomization.yaml"

if [[ -f "$OVERLAY" ]]; then
  BACKUP="$OVERLAY.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$OVERLAY" "$BACKUP"
  echo "💾 Ancien kustomization sauvegardé : $BACKUP"
fi

# ─────────────────────────────────────────────
# 3. Créer le nouvel overlay
# ─────────────────────────────────────────────

cat >"$OVERLAY" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../apps/demo
EOF

echo "✅ infra/overlays/tests/kustomization.yaml modifié"

# ─────────────────────────────────────────────
# 4. Créer le dossier des patches
# ─────────────────────────────────────────────

mkdir -p "$ROOT/infra/overlays/tests/patches"

echo "✅ patches/ créé"

# ─────────────────────────────────────────────
# 5. Vérification Kustomize
# ─────────────────────────────────────────────

echo
echo "🔍 Test Kustomize..."

if k kustomize "$ROOT/infra/overlays/tests/" >/tmp/kustomize-tests.yaml; then
  echo "✅ Kustomize OK"
  echo
  echo "📦 Manifests générés :"
  grep '^kind:' /tmp/kustomize-tests.yaml | sort | uniq -c
else
  echo "❌ Kustomize échoue"
  exit 1
fi

echo
echo "🎉 Migration terminée"
echo
echo "Pour appliquer :"
echo "  k apply -k infra/overlays/tests/"
echo
echo "Pour supprimer :"
echo "  k delete -k infra/overlays/tests/"
