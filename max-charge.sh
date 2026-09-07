#!/bin/bash

set -u

NAMESPACE="dev"
LOAD_POD="load-generator"

PROM_NAMESPACE="tools"
PROM_SERVICE="prometheus"
PROM_LOCAL_PORT="9090"
PROM_REMOTE_PORT="9090"

# Durée de chaque étape
DURATION=120

# Tests
RATES=(10 50 100 200 500)

PORT_FORWARD_PID=""
WATCH_PID=""
LOAD_LOG_PID=""
KUBECTL_LOGS_PID=""

declare -A RATE_START_TIMES
declare -A RATE_END_TIMES
SAMPLES_FILE="/tmp/load_samples.log"

cleanup() {
  echo
  echo "========================================"
  echo " Nettoyage"
  echo "========================================"

  if [ -n "${LOAD_LOG_PID}" ]; then
    kill "${LOAD_LOG_PID}" 2>/dev/null || true
    wait "${LOAD_LOG_PID}" 2>/dev/null || true
  fi

  if [ -n "${KUBECTL_LOGS_PID}" ]; then
    kill "${KUBECTL_LOGS_PID}" 2>/dev/null || true
    wait "${KUBECTL_LOGS_PID}" 2>/dev/null || true
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

  rm -f "${SAMPLES_FILE}"
  rm -f /tmp/load_generator.log
  rm -f /tmp/curl_results.log
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
# 1. Port-forward Prometheus (only once)
# --------------------------------------------------

echo "[1/6] Démarrage du port-forward Prometheus..."

# Check if port already in use
if ! curl -fsS "http://127.0.0.1:${PROM_LOCAL_PORT}/-/ready" >/dev/null 2>&1; then
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
else
  echo "Port-forward déjà actif, on le réutilise."
fi

echo "OK : Prometheus accessible."
echo

# --------------------------------------------------
# 2. Vérification du service nginx
# --------------------------------------------------

echo "[2/6] Vérification du service nginx..."

# Vérifier que le service nginx existe
if ! kubectl -n "${NAMESPACE}" get svc nginx-service >/dev/null 2>&1; then
  echo "ERREUR : le service nginx-service n'existe pas dans le namespace ${NAMESPACE}"
  exit 1
fi

echo "OK : Service nginx-service trouvé."
echo

# --------------------------------------------------
# 3. Démarrage de la surveillance des ressources
# --------------------------------------------------

echo "[3/6] Démarrage de la surveillance des ressources..."

: >"${SAMPLES_FILE}" # reset samples file

monitor_resources() {
  while true; do
    # Only monitor nginx pods; ignore load-generator and other pods
    METRICS=$(kubectl top pods -n "${NAMESPACE}" --no-headers 2>/dev/null |
      awk '$1 ~ /^nginx-/ {print}' || echo "")

    if [ -n "$METRICS" ]; then
      TOTAL_CPU="0"
      TOTAL_MEM="0"

      while read -r POD CPU MEM; do
        # Convert CPU: "100m" -> "0.100", "1" -> "1.000"
        CPU_NUM=$(echo "$CPU" | sed 's/m$//')
        if [[ "$CPU" == *m ]]; then
          CPU_NUM=$(echo "scale=3; $CPU_NUM / 1000" | bc)
        fi

        # Convert MEM: "100Mi" -> "100"
        MEM_NUM=$(echo "$MEM" | sed 's/Mi$//')

        TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU_NUM" | bc)
        TOTAL_MEM=$(echo "$TOTAL_MEM + $MEM_NUM" | bc)
      done <<<"$METRICS"

      TIMESTAMP=$(date +%s)
      echo "$TIMESTAMP $TOTAL_CPU $TOTAL_MEM" >>"${SAMPLES_FILE}"
    fi

    sleep 2
  done
}

# Lancer la surveillance en arrière-plan
monitor_resources &
MONITOR_PID=$!

echo "OK : Surveillance démarrée (PID ${MONITOR_PID})."
echo

# --------------------------------------------------
# 4. Création du load generator
# --------------------------------------------------

echo "[4/6] Création du load-generator..."

# Record the start time of the whole load test
START=$(date +%s)

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

    echo "MARKER_START_${RATE} $(date +%s)"
    echo
    echo "========================================"
    echo "LOAD ${RATE} req/s - ${DURATION}s"
    echo "========================================"

    # Temps de début
    START_TIME=$(date +%s)
    END_TIME=$((START_TIME + DURATION))

    RESULTS_FILE="/tmp/curl_results.log"
    : > "${RESULTS_FILE}"

    # Send batches of RATE requests every second for DURATION seconds.
    # The previous version waited for all requests of a batch to finish
    # before starting the next batch, which artificially limited the
    # achieved request rate. Now we do not wait between batches; we sleep
    # exactly 1 second after starting each batch, then count all results
    # only after the whole stage has finished.
    while [ "$(date +%s)" -lt "$END_TIME" ]; do
        i=0
        while [ "$i" -lt "$RATE" ]; do
            (
                if curl -s \
                    -o /dev/null \
                    --connect-timeout 1 \
                    --max-time 2 \
                    --fail \
                    "http://nginx-service:8080/hello"; then
                    echo "OK" >> "${RESULTS_FILE}"
                else
                    echo "FAIL" >> "${RESULTS_FILE}"
                fi
            ) &
            i=$((i + 1))
        done

        # Wait one second before sending the next batch
        sleep 1
    done

    # Wait for all in-flight requests to finish
    wait || true

    # Count results by reading the output file
    OK_COUNT=$(grep -c "OK" "${RESULTS_FILE}" 2>/dev/null)
    FAIL_COUNT=$(grep -c "FAIL" "${RESULTS_FILE}" 2>/dev/null)
    OK_COUNT=${OK_COUNT:-0}
    FAIL_COUNT=${FAIL_COUNT:-0}

    TOTAL=$((TOTAL + OK_COUNT))
    ERRORS=$((ERRORS + FAIL_COUNT))

    # Clean temporary file
    rm -f "${RESULTS_FILE}"

    echo
    echo "RESULTAT pour ${RATE} req/s :"
    echo "  - Total requêtes : ${TOTAL}"
    echo "  - Erreurs        : ${ERRORS}"
    if [ "$TOTAL" -gt 0 ]; then
        echo "  - Taux de succès : $(( (TOTAL - ERRORS) * 100 / TOTAL ))%"
    else
        echo "  - Taux de succès : N/A (aucune requête)"
    fi

    if [ "$ERRORS" -gt 0 ]; then
        echo "ERREUR : ${ERRORS} requêtes ont échoué sur ${TOTAL}"
        echo "MARKER_END_${RATE} $(date +%s)"
        return 1
    fi

    echo "SUCCÈS : ${TOTAL} requêtes, 0 erreur"
    echo "MARKER_END_${RATE} $(date +%s)"
    return 0
}

# Test initial pour vérifier la connectivité
echo "Test de connectivité initial..."
if ! curl -s -o /dev/null --connect-timeout 2 --max-time 3 "http://nginx-service:8080/hello"; then
    echo "ERREUR : Impossible de joindre nginx-service"
    exit 1
fi
echo "Connectivité OK"
echo

# Exécuter les tests de charge
for RATE in 10 50 100 200 500; do
    run_load "$RATE" 120 || exit 1
    echo
done

echo
echo "========================================"
echo "LOAD TEST TERMINE"
echo "========================================"
'

# --------------------------------------------------
# 5. Attente Ready
# --------------------------------------------------

echo "[5/6] Attente du load-generator..."

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Running \
  "pod/${LOAD_POD}" \
  --timeout=60s

echo "OK : load-generator Running."
echo

# --------------------------------------------------
# 6. Suivi des logs pour affichage et détection des marqueurs
# --------------------------------------------------

echo "[6/6] Démarrage du suivi des logs..."

# Capture les logs dans un fichier temporaire pour les traiter
LOG_FILE="/tmp/load_generator.log"
: >"${LOG_FILE}"

kubectl -n "${NAMESPACE}" logs -f "${LOAD_POD}" 2>&1 >"${LOG_FILE}" &
KUBECTL_LOGS_PID=$!

# Afficher les logs en direct (sans modifier les tableaux du parent)
tail -n +1 -f "${LOG_FILE}" &
LOAD_LOG_PID=$!

# Attendre la fin du test
kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/${LOAD_POD}" \
  --timeout=15m

END=$(date +%s)

echo
echo "END = ${END}"
echo

# Arrêter la surveillance et le suivi des logs
kill "${MONITOR_PID}" 2>/dev/null || true
wait "${MONITOR_PID}" 2>/dev/null || true

kill "${LOAD_LOG_PID}" 2>/dev/null || true
wait "${LOAD_LOG_PID}" 2>/dev/null || true

kill "${KUBECTL_LOGS_PID}" 2>/dev/null || true
wait "${KUBECTL_LOGS_PID}" 2>/dev/null || true

# --------------------------------------------------
# Extraction des temps de début/fin de chaque niveau
# --------------------------------------------------
for rate in "${RATES[@]}"; do
  start_line=$(grep -m1 "MARKER_START_${rate}" "${LOG_FILE}" || true)
  end_line=$(grep -m1 "MARKER_END_${rate}" "${LOG_FILE}" || true)

  if [ -n "$start_line" ]; then
    RATE_START_TIMES[$rate]=$(echo "$start_line" | awk '{print $NF}')
  else
    RATE_START_TIMES[$rate]=0
  fi

  if [ -n "$end_line" ]; then
    RATE_END_TIMES[$rate]=$(echo "$end_line" | awk '{print $NF}')
  else
    RATE_END_TIMES[$rate]=0
  fi
done

# --------------------------------------------------
# Helpers for percentile calculation
# --------------------------------------------------
get_percentile() {
  # $1: sorted values (one per line)
  # $2: percentile as integer 0-100
  # Outputs the requested percentile value
  local values="$1"
  local p="$2"

  echo "$values" | sort -n | awk -v p="$p" '
    BEGIN { n = 0 }
    { a[n++] = $1 }
    END {
      if (n == 0) {
        print "0"
      } else {
        # Linear interpolation between closest ranks
        idx = (p / 100.0) * (n - 1)
        lower = int(idx)
        upper = (lower + 1 < n) ? lower + 1 : lower
        frac = idx - lower
        print a[lower] + frac * (a[upper] - a[lower])
      }
    }'
}

# Bilan final
echo
echo "========================================"
echo " BILAN FINAL"
echo "========================================"
echo
echo "Début : $(date -d "@${START}")"
echo "Fin   : $(date -d "@${END}")"
echo

# Calculer les maximums et percentiles par niveau de requêtes
echo "=== Charges maximales et percentiles par niveau ==="
for rate in "${RATES[@]}"; do
  st="${RATE_START_TIMES[$rate]:-0}"
  et="${RATE_END_TIMES[$rate]:-0}"

  if [ "$st" -gt 0 ] && [ "$et" -gt 0 ] && [ "$et" -ge "$st" ]; then
    # Maximums (existing behaviour)
    max_cpu=$(awk -v start="$st" -v end="$et" '$1 >= start && $1 <= end {if ($2 > max_cpu) max_cpu=$2} END {if (max_cpu=="") max_cpu=0; print max_cpu}' "${SAMPLES_FILE}")
    max_mem=$(awk -v start="$st" -v end="$et" '$1 >= start && $1 <= end {if ($3 > max_mem) max_mem=$3} END {if (max_mem=="") max_mem=0; print max_mem}' "${SAMPLES_FILE}")

    # Extract values in the time window
    cpu_values=$(awk -v start="$st" -v end="$et" '$1 >= start && $1 <= end {print $2}' "${SAMPLES_FILE}")
    mem_values=$(awk -v start="$st" -v end="$et" '$1 >= start && $1 <= end {print $3}' "${SAMPLES_FILE}")

    # Percentiles
    cpu_p50=$(get_percentile "$cpu_values" 50)
    cpu_p95=$(get_percentile "$cpu_values" 95)
    cpu_p99=$(get_percentile "$cpu_values" 99)
    mem_p50=$(get_percentile "$mem_values" 50)
    mem_p95=$(get_percentile "$mem_values" 95)
    mem_p99=$(get_percentile "$mem_values" 99)

    echo "  Rate ${rate} req/s :"
    echo "    CPU max ${max_cpu} cores | p50 ${cpu_p50} p95 ${cpu_p95} p99 ${cpu_p99} cores"
    echo "    MEM max ${max_mem} Mi   | p50 ${mem_p50} p95 ${mem_p95} p99 ${mem_p99} Mi"
  else
    echo "  Rate ${rate} req/s : données manquantes (st=${st}, et=${et})"
  fi
done

# Calculer les maximums globaux
overall_cpu=$(awk 'BEGIN {max=0} {if ($2 > max) max=$2} END {print max}' "${SAMPLES_FILE}")
overall_mem=$(awk 'BEGIN {max=0} {if ($3 > max) max=$3} END {print max}' "${SAMPLES_FILE}")

echo
echo "=== Charge maximale globale ==="
echo "  CPU maximale      : ${overall_cpu} cores"
echo "  Mémoire maximale  : ${overall_mem} Mi"
echo

# Afficher une dernière fois les ressources
echo "=== Ressources finales ==="
kubectl top pods -n "${NAMESPACE}" --sort-by=cpu 2>/dev/null ||
  echo "kubectl top indisponible (metrics-server ?)"

echo
echo "========================================"
echo " TEST TERMINE"
echo "========================================"
