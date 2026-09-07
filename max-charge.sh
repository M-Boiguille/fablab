#!/bin/bash

set -u

NAMESPACE="dev"
LOAD_POD="load-generator"

PROM_NAMESPACE="tools"
PROM_SERVICE="prometheus"
PROM_LOCAL_PORT="9090"
PROM_REMOTE_PORT="9090"

MAX_CHARGE="./max-charge.sh"

# Durée de chaque étape
DURATION=8

# Tests
RATES=(10 50 100 200 500)

PORT_FORWARD_PID=""
WATCH_PID=""
LOAD_LOG_PID=""

START=""
END=""

cleanup() {
  echo
  echo "========================================"
  echo " Nettoyage"
  echo "========================================"

  if [ -n "${LOAD_LOG_PID}" ]; then
    kill "${LOAD_LOG_PID}" 2>/dev/null || true
    wait "${LOAD_LOG_PID}" 2>/dev/null || true
  fi

  if [ -n "${WATCH_PID}" ]; then
    kill "${WATCH_PID}" 2>/dev/null || true
    wait "${WATCH_PID}" 2>/dev/null || true
  fi

  if [ -n "${PORT_FORWARD_PID}" ]; then
    kill "${PORT_FORWARD_PID}" 2>/dev/null || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi

  kubectl -n "${NAMESPACE}" delete pod "${LOAD_POD}" \
    --ignore-not-found=true \
    --wait=false >/dev/null 2>&1 || true

  echo "Nettoyage terminé."
}

trap cleanup EXIT INT TERM

echo "========================================"
echo " Kubernetes load test"
echo "========================================"
echo
echo "Namespace       : ${NAMESPACE}"
echo "Prometheus      : ${PROM_NAMESPACE}/${PROM_SERVICE}"
echo "Local Prometheus: http://127.0.0.1:${PROM_LOCAL_PORT}"
echo "Rates           : ${RATES[*]}"
echo "Durée/stage     : ${DURATION}s"
echo

# --------------------------------------------------
# 1. Port-forward Prometheus
# --------------------------------------------------

echo "[1/6] Démarrage du port-forward Prometheus..."

kubectl -n "${PROM_NAMESPACE}" port-forward \
  "svc/${PROM_SERVICE}" \
  "${PROM_LOCAL_PORT}:${PROM_REMOTE_PORT}" \
  >/tmp/prometheus-port-forward.log 2>&1 &

PORT_FORWARD_PID=$!

sleep 2

if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
  echo "ERREUR : le port-forward Prometheus n'a pas démarré."
  cat /tmp/prometheus-port-forward.log
  exit 1
fi

if ! curl -fsS \
  "http://127.0.0.1:${PROM_LOCAL_PORT}/-/ready" \
  >/dev/null; then

  echo "ERREUR : Prometheus n'est pas accessible."
  cat /tmp/prometheus-port-forward.log
  exit 1
fi

echo "OK : Prometheus accessible."
echo

# --------------------------------------------------
# 2. Création du load generator
# --------------------------------------------------

echo "[2/6] Création du load-generator..."

kubectl -n "${NAMESPACE}" delete pod "${LOAD_POD}" \
  --ignore-not-found=true \
  --wait=true >/dev/null 2>&1 || true

kubectl -n "${NAMESPACE}" run "${LOAD_POD}" \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --command -- sh -c '

run_load() {
    RATE="$1"
    DURATION="$2"

    TOTAL=0
    ERRORS=0

    echo
    echo "========================================"
    echo "LOAD ${RATE} req/s - ${DURATION}s"
    echo "========================================"

    END_TIME=$((SECONDS + DURATION))

    while [ "$SECONDS" -lt "$END_TIME" ]; do

        i=0

        while [ "$i" -lt "$RATE" ]; do
            (
                curl -s \
                    -o /dev/null \
                    --connect-timeout 1 \
                    --max-time 2 \
                    --fail \
                    "http://nginx-service:8080/hello"
            ) &

            i=$((i + 1))
        done

        wait || true

        TOTAL=$((TOTAL + RATE))

        sleep 1
    done

    echo "RESULTAT : ${TOTAL} requêtes"

    if [ "$ERRORS" -gt 0 ]; then
        echo "ERREUR : ${ERRORS} requêtes ont échoué sur ${TOTAL}"
        return 1
    fi

    echo "SUCCÈS : ${TOTAL} requêtes, 0 erreur"
    return 0
}

run_load 10 8 || exit 1
run_load 50 8 || exit 1
run_load 100 8 || exit 1
run_load 200 8 || exit 1
run_load 500 8 || exit 1

echo
echo "========================================"
echo "LOAD TEST TERMINE"
echo "========================================"
'

# --------------------------------------------------
# 3. Attente Ready
# --------------------------------------------------

echo "[3/6] Attente du load-generator..."

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Running \
  "pod/${LOAD_POD}" \
  --timeout=60s

echo "OK : load-generator Running."
echo

# --------------------------------------------------
# 4. START + watch
# --------------------------------------------------

echo "[4/6] Démarrage de la mesure..."

START=$(date +%s)

echo "START = ${START}"
echo

(
  while true; do
    clear

    echo "========================================"
    echo " RESOURCE WATCH"
    echo "========================================"
    echo "Depuis : $(date -d "@${START}")"
    echo "Maintenant : $(date)"
    echo

    "${MAX_CHARGE}" "${START}" "$(date +%s)"

    sleep 5
  done
) &

WATCH_PID=$!

# Affichage des logs du load-generator
kubectl -n "${NAMESPACE}" logs -f "${LOAD_POD}" 2>&1 |
  sed 's/^/[LOAD] /' &

LOAD_LOG_PID=$!

# --------------------------------------------------
# 5. Attente de la fin du test
# --------------------------------------------------

echo "[5/6] Test en cours..."

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/${LOAD_POD}" \
  --timeout=15m

END=$(date +%s)

echo
echo "END = ${END}"
echo

# --------------------------------------------------
# 6. Bilan final
# --------------------------------------------------

echo "[6/6] Bilan final..."

if [ -n "${WATCH_PID}" ]; then
  kill "${WATCH_PID}" 2>/dev/null || true
  wait "${WATCH_PID}" 2>/dev/null || true
  WATCH_PID=""
fi

if [ -n "${LOAD_LOG_PID}" ]; then
  kill "${LOAD_LOG_PID}" 2>/dev/null || true
  wait "${LOAD_LOG_PID}" 2>/dev/null || true
  LOAD_LOG_PID=""
fi

echo
echo "========================================"
echo " BILAN FINAL"
echo "========================================"
echo
echo "Début : $(date -d "@${START}")"
echo "Fin   : $(date -d "@${END}")"
echo

"${MAX_CHARGE}" "${START}" "${END}"

echo
echo "========================================"
echo " TEST TERMINE"
echo "========================================"
