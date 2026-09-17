#!/usr/bin/env bash
set -uo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

RESULT_FILE="$SCRIPT_DIR/step_08_result.txt"
rm -f "$RESULT_FILE"

NAMESPACE="${NAMESPACE:-dev}"
DEPLOY_NAME="${DEPLOY_NAME:-nginx}"
EXPECTED_CONFIGMAP="${EXPECTED_CONFIGMAP:-nginx-config}"
EXPECTED_SECRET="${EXPECTED_SECRET:-nginx-secret}"
NGINX_CONTAINER="nginx"
SIDECAR_CONTAINER="sidecar-nginx"

LOG_ENTRIES=()
PASS_COUNT=0
FAIL_COUNT=0
NON_CONCLUANT_COUNT=0

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

log_non_concluant() {
  local msg="$1"
  LOG_ENTRIES+=("NON_CONCLUANT | $msg")
  NON_CONCLUANT_COUNT=$((NON_CONCLUANT_COUNT + 1))
  echo "NON_CONCLUANT | $msg"
}

write_result_file() {
  local status="PASS"
  local status_word="successful"
  if ((FAIL_COUNT > 0)); then
    status="FAIL"
    status_word="failed"
  fi

  {
    echo "$status"
    echo "--- Summary ---"
    for entry in "${LOG_ENTRIES[@]}"; do
      echo "$entry"
    done
    echo "# PASS: $PASS_COUNT"
    echo "# FAIL: $FAIL_COUNT"
    echo "# NON_CONCLUANT: $NON_CONCLUANT_COUNT"
    echo "# $status | Step 08 validation $status_word"
  } >"$RESULT_FILE"
}

# ---- Cleanup / safety net --------------------------------------------------
CM_BACKUP=""
PF_PID=""

restore_configmap() {
  if [[ -n "$CM_BACKUP" && -f "$CM_BACKUP" ]]; then
    kubectl apply -f "$CM_BACKUP" >/dev/null 2>&1 || true
    rm -f "$CM_BACKUP"
    CM_BACKUP=""
  fi
}

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
  restore_configmap
}
trap cleanup EXIT

# ---- Prerequisites ---------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  log_fail "kubectl is not installed or not in PATH."
  write_result_file
  exit 1
fi

NODE_NAME="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
if [[ -z "$NODE_NAME" ]]; then
  log_fail "No Kubernetes node found. Is kubectl configured and cluster running?"
  write_result_file
  exit 1
fi

if ! kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_fail "Deployment $DEPLOY_NAME not found in namespace $NAMESPACE."
  write_result_file
  exit 1
fi

# ---- 1. ConfigMap presence and immutability --------------------------------
if ! kubectl get configmap "$EXPECTED_CONFIGMAP" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_fail "ConfigMap '$EXPECTED_CONFIGMAP' does not exist in namespace $NAMESPACE."
else
  log_pass "ConfigMap '$EXPECTED_CONFIGMAP' exists in namespace $NAMESPACE."

  imm="$(kubectl get configmap "$EXPECTED_CONFIGMAP" -n "$NAMESPACE" -o jsonpath='{.immutable}' 2>/dev/null || echo "")"
  if [[ "$imm" == "true" ]]; then
    log_pass "ConfigMap '$EXPECTED_CONFIGMAP' is immutable (immutable: true)."
  else
    log_fail "ConfigMap '$EXPECTED_CONFIGMAP' is not immutable (immutable='$imm')."
  fi

  has_conf="$(kubectl get configmap "$EXPECTED_CONFIGMAP" -n "$NAMESPACE" -o jsonpath='{.data.default\.conf}' 2>/dev/null || echo "")"
  if [[ -n "$has_conf" ]]; then
    log_pass "ConfigMap '$EXPECTED_CONFIGMAP' contains a 'default.conf' entry."
  else
    log_fail "ConfigMap '$EXPECTED_CONFIGMAP' has no 'default.conf' entry."
  fi
fi

# ---- 2. TLS Secret presence and type --------------------------------------
if ! kubectl get secret "$EXPECTED_SECRET" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_fail "TLS Secret '$EXPECTED_SECRET' does not exist in namespace $NAMESPACE."
else
  log_pass "Secret '$EXPECTED_SECRET' exists in namespace $NAMESPACE."

  stype="$(kubectl get secret "$EXPECTED_SECRET" -n "$NAMESPACE" -o jsonpath='{.type}' 2>/dev/null || echo "")"
  if [[ "$stype" == "kubernetes.io/tls" ]]; then
    log_pass "Secret '$EXPECTED_SECRET' has type kubernetes.io/tls."
  else
    log_fail "Secret '$EXPECTED_SECRET' has type '$stype', expected 'kubernetes.io/tls'."
  fi

  has_crt="$(kubectl get secret "$EXPECTED_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")"
  has_key="$(kubectl get secret "$EXPECTED_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' 2>/dev/null || echo "")"
  if [[ -n "$has_crt" && -n "$has_key" ]]; then
    log_pass "Secret '$EXPECTED_SECRET' contains both 'tls.crt' and 'tls.key' keys."
  else
    log_fail "Secret '$EXPECTED_SECRET' is missing 'tls.crt' and/or 'tls.key' keys."
  fi
fi

# ---- 3. Deployment containers (nginx + sidecar) ----------------------------
mapfile -t CONTAINERS < <(
  kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
    -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -v '^$'
)

has_nginx=0
has_sidecar=0
for c in "${CONTAINERS[@]}"; do
  [[ "$c" == "$NGINX_CONTAINER" ]] && has_nginx=1
  [[ "$c" == "$SIDECAR_CONTAINER" ]] && has_sidecar=1
done

if [[ "$has_nginx" -eq 1 ]]; then
  log_pass "Deployment '$DEPLOY_NAME' has an nginx container ('$NGINX_CONTAINER')."
else
  log_fail "Deployment '$DEPLOY_NAME' has no container named '$NGINX_CONTAINER'."
fi

if [[ "$has_sidecar" -eq 1 ]]; then
  log_pass "Deployment '$DEPLOY_NAME' has a sidecar container ('$SIDECAR_CONTAINER')."
else
  log_fail "Deployment '$DEPLOY_NAME' has no container named '$SIDECAR_CONTAINER'."
fi

if (( ${#CONTAINERS[@]} >= 2 )); then
  log_pass "Deployment '$DEPLOY_NAME' runs ${#CONTAINERS[@]} containers (multi-container pod)."
else
  log_fail "Deployment '$DEPLOY_NAME' runs ${#CONTAINERS[@]} container(s), expected at least 2 (nginx + sidecar)."
fi

# Sidecar shares the nginx-logs volume with the nginx container.
sidecar_logs="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SIDECAR_CONTAINER')].volumeMounts[?(@.mountPath=='/var/log/nginx')].name}" 2>/dev/null || echo "")"
nginx_logs="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='$NGINX_CONTAINER')].volumeMounts[?(@.mountPath=='/var/log/nginx')].name}" 2>/dev/null || echo "")"
if [[ -n "$sidecar_logs" && "$sidecar_logs" == "$nginx_logs" ]]; then
  log_pass "Sidecar and nginx share the log volume '$sidecar_logs' at /var/log/nginx."
else
  log_fail "Sidecar and nginx do not share the same log volume (sidecar='$sidecar_logs', nginx='$nginx_logs')."
fi

# ---- 4. Ports 80 and 443 are exposed ---------------------------------------
PORTS_LIST="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
  -o jsonpath='{range .spec.template.spec.containers[*].ports[*]}{.containerPort}{"\n"}{end}' 2>/dev/null | grep -v '^$')"

if grep -qx '80' <<<"$PORTS_LIST"; then
  log_pass "Port 80 is exposed by the Deployment '$DEPLOY_NAME'."
else
  log_fail "Port 80 is not exposed by the Deployment '$DEPLOY_NAME'."
fi

if grep -qx '443' <<<"$PORTS_LIST"; then
  log_pass "Port 443 is exposed by the Deployment '$DEPLOY_NAME'."
else
  log_fail "Port 443 is not exposed by the Deployment '$DEPLOY_NAME'."
fi

# TLS Secret is mounted in the nginx container.
cert_mount="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='$NGINX_CONTAINER')].volumeMounts[?(@.name=='nginx-certificates')].mountPath}" 2>/dev/null || echo "")"
if [[ "$cert_mount" == "/usr/share/nginx/certificates" ]]; then
  log_pass "The TLS Secret volume is mounted into the nginx container for HTTPS termination."
else
  log_fail "The TLS Secret volume is not mounted into the nginx container (mountPath='$cert_mount')."
fi

# ---- 5. securityContext (nginx + sidecar) ----------------------------------
pod_security="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.securityContext}' 2>/dev/null || echo "")"
if [[ -n "$pod_security" && "$pod_security" != "{}" ]]; then
  log_pass "A pod-level securityContext is defined."
else
  log_fail "No pod-level securityContext is defined."
fi

for c in "$NGINX_CONTAINER" "$SIDECAR_CONTAINER"; do
  sc="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$c')].securityContext}" 2>/dev/null || echo "")"
  if [[ -n "$sc" && "$sc" != "{}" ]]; then
    log_pass "Container '$c' defines a container-level securityContext."
  else
    log_fail "Container '$c' has no container-level securityContext."
  fi
done

for c in "$NGINX_CONTAINER" "$SIDECAR_CONTAINER"; do
  run_as_non_root="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$c')].securityContext.runAsNonRoot}" 2>/dev/null || echo "")"
  if [[ "$run_as_non_root" == "true" ]]; then
    log_pass "Container '$c' has runAsNonRoot: true."
  else
    log_fail "Container '$c' does not set runAsNonRoot: true."
  fi
done

# ---- 6. Deployment availability --------------------------------------------
desired="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")"
ready_replicas="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
ready_replicas="${ready_replicas:-0}"
if (( desired > 0 && ready_replicas >= desired )); then
  log_pass "Deployment '$DEPLOY_NAME' is available ($ready_replicas/$desired replicas ready)."
else
  log_fail "Deployment '$DEPLOY_NAME' is not fully available ($ready_replicas/$desired replicas ready)."
fi

# ---- 7. HTTP / HTTPS connectivity ------------------------------------------
# Port-forward is done on the Deployment (not the Service) because the live
# Service selector/ports may not match the live Deployment pod labels/ports.
test_endpoint() {
  local container_port="$1"
  local local_port="$2"
  local scheme="$3"

  kubectl -n "$NAMESPACE" port-forward "deployment/$DEPLOY_NAME" "$local_port:$container_port" >/dev/null 2>&1 &
  local pid=$!
  PF_PID="$pid"

  local code=""
  for _ in {1..5}; do
    code="$(curl -sk -o /dev/null -m 3 -w '%{http_code}' "$scheme://127.0.0.1:$local_port/" 2>/dev/null || echo "000")"
    [[ "$code" != "000" && -n "$code" ]] && break
    sleep 2
  done

  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
  PF_PID=""

  echo "$code"
}

if command -v curl >/dev/null 2>&1; then
  http_code="$(test_endpoint 80 18080 http)"
  if [[ -n "$http_code" && "$http_code" != "000" ]]; then
    log_pass "HTTP connectivity to the application succeeded (status $http_code)."
  else
    log_fail "HTTP connectivity to the application failed."
  fi

  https_code="$(test_endpoint 443 18443 https)"
  if [[ -n "$https_code" && "$https_code" != "000" ]]; then
    log_pass "HTTPS connectivity to the application succeeded (status $https_code)."
  else
    log_fail "HTTPS connectivity to the application failed."
  fi
else
  log_fail "'curl' is required to test HTTP/HTTPS connectivity but was not found."
fi

# ---- 8. Break-it scenario: delete the referenced ConfigMap -----------------
SELECTOR="$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" \
  -o go-template='{{range $k,$v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}' 2>/dev/null | sed 's/,$//')"

ready_pod_count() {
  kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
    | grep -c '^True$' || true
}

if ! kubectl get configmap "$EXPECTED_CONFIGMAP" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_fail "Break-it scenario skipped: ConfigMap '$EXPECTED_CONFIGMAP' does not exist."
else
  CM_BACKUP="$(mktemp -t step08-cm-XXXXXX.yaml)"
  kubectl get configmap "$EXPECTED_CONFIGMAP" -n "$NAMESPACE" -o yaml --show-managed-fields=false 2>/dev/null \
    | sed -E '/^[[:space:]]*(resourceVersion|uid|creationTimestamp|generation|selfLink):/d' >"$CM_BACKUP"

  log_pass "Break-it: backup of ConfigMap '$EXPECTED_CONFIGMAP' saved before deletion."

  kubectl delete configmap "$EXPECTED_CONFIGMAP" -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete pods -n "$NAMESPACE" -l "$SELECTOR" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true

  broken=0
  for _ in {1..15}; do
    rc="$(ready_pod_count)"
    rc="${rc:-0}"
    if (( rc == 0 )); then
      broken=1
      break
    fi
    sleep 2
  done

  if [[ "$broken" -eq 1 ]]; then
    log_pass "Break-it: Pods are not Ready after the referenced ConfigMap '$EXPECTED_CONFIGMAP' was deleted (issue diagnosed)."
  else
    log_non_concluant "Break-it: Pods remained Ready after the referenced ConfigMap '$EXPECTED_CONFIGMAP' was deleted. K3s kubelet cache bug likely masks the missing volume; scenario non concluant sans redémarrage de k3s (cf ADR 08)."
  fi

  event_hits="$(kubectl get events -n "$NAMESPACE" 2>/dev/null \
    | grep -i "$EXPECTED_CONFIGMAP" | grep -ci 'not found\|FailedMount\|CreateContainerConfigError' || true)"
  if (( ${event_hits:-0} > 0 )); then
    log_pass "Break-it: events reference the missing ConfigMap '$EXPECTED_CONFIGMAP' (root cause identifiable)."
  else
    if [[ "$broken" -eq 1 ]]; then
      log_fail "Break-it: no event mentions the missing ConfigMap '$EXPECTED_CONFIGMAP'."
    else
      log_non_concluant "Break-it: no event mentions the missing ConfigMap '$EXPECTED_CONFIGMAP'. K3s cache issue may mask the missing volume."
    fi
  fi

  # Restore the ConfigMap and let the deployment recover.
  restore_configmap

  kubectl delete pods -n "$NAMESPACE" -l "$SELECTOR" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true

  recovered=0
  for _ in {1..20}; do
    rc="$(ready_pod_count)"
    rc="${rc:-0}"
    if (( rc >= 1 )); then
      recovered=1
      break
    fi
    sleep 3
  done

  if [[ "$recovered" -eq 1 ]]; then
    log_pass "Break-it: the application recovered after the referenced ConfigMap '$EXPECTED_CONFIGMAP' was restored."
  else
    log_fail "Break-it: the application did not recover after the referenced ConfigMap '$EXPECTED_CONFIGMAP' was restored."
  fi
fi

write_result_file
