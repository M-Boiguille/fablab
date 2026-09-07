#!/bin/bash

set -Eeuo pipefail

# ==============================
# Configuration
# ==============================
NAMESPACE="dev"
LOAD_POD="load-generator"
PROM_NAMESPACE="tools"
PROM_SERVICE="prometheus"
PROM_LOCAL_PORT="9090"
PROM_REMOTE_PORT="9090"

RATES=(10 50 100 200 500)

# Durée de chaque palier
WARMUP_SECONDS=60
MEASURE_SECONDS=120
STAGE_DURATION=$((WARMUP_SECONDS + MEASURE_SECONDS))

PROM_STEP_SECONDS=15

SAFETY_MARGIN_PERCENT=50

# Fichiers temporaires
LOG_FILE="/tmp/load_generator.log"
CURL_RESULTS_FILE="/tmp/curl_results.log"
SAMPLES_FILE="/tmp/load_samples.log"

# Variables de processus
PORT_FORWARD_PID=""
KUBECTL_LOGS_PID=""
LOAD_LOG_PID=""

# Tableaux associatifs
declare -A STAGE_START
declare -A MEASURE_START
declare -A STAGE_END

# ==============================
# Fonctions utilitaires
# ==============================
check_dependencies() {
  for cmd in kubectl curl jq awk sort grep date sed wc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERREUR : $cmd est requis mais introuvable." >&2
      exit 1
    fi
  done
}

cleanup() {
  echo
  echo "========================================"
  echo " Nettoyage"
  echo "========================================"

  [ -n "${LOAD_LOG_PID}" ] && kill "${LOAD_LOG_PID}" 2>/dev/null || true
  [ -n "${KUBECTL_LOGS_PID}" ] && kill "${KUBECTL_LOGS_PID}" 2>/dev/null || true
  [ -n "${PORT_FORWARD_PID}" ] && kill "${PORT_FORWARD_PID}" 2>/dev/null || true

  kubectl -n "${NAMESPACE}" delete pod "${LOAD_POD}" \
    --ignore-not-found=true \
    --wait=false >/dev/null 2>&1 || true

  rm -f "${SAMPLES_FILE}" "${LOG_FILE}" "${CURL_RESULTS_FILE}"
  echo "Nettoyage terminé."
}

trap cleanup EXIT INT TERM

prom_query_range() {
  local query="$1"
  local start="$2"
  local end="$3"
  local step="$4"

  curl -fsS --get "http://127.0.0.1:${PROM_LOCAL_PORT}/api/v1/query_range" \
    --data-urlencode "query=${query}" \
    --data-urlencode "start=${start}" \
    --data-urlencode "end=${end}" \
    --data-urlencode "step=${step}"
}

get_percentile() {
  local values="$1"
  local p="$2"

  printf '%s\n' "$values" | sort -n | awk -v p="$p" '
    {
      a[NR] = $1
    }
    END {
      n = NR
      if (n == 0) {
        print 0
        exit
      }
      idx = p / 100.0 * (n - 1)
      lower = int(idx)
      upper = (lower + 1 < n) ? lower + 1 : lower
      frac = idx - lower
      if (lower + 1 <= n && upper + 1 <= n) {
        print a[lower+1] + frac * (a[upper+1] - a[lower+1])
      } else {
        print a[lower+1]
      }
    }'
}

compute_stats() {
  local values="$1"

  # Supprime les lignes vides
  values=$(printf '%s\n' "$values" | sed '/^[[:space:]]*$/d')

  local count max p50 p95 p99
  count=$(printf '%s\n' "$values" | wc -l)

  if [ "$count" -eq 0 ]; then
    echo "0 0 0 0 0"
    return
  fi

  max=$(printf '%s\n' "$values" | awk 'BEGIN{max=-1e9} {if ($1>max) max=$1} END{if(max==-1e9)max=0; print max}')
  p50=$(get_percentile "$values" 50)
  p95=$(get_percentile "$values" 95)
  p99=$(get_percentile "$values" 99)

  echo "$count $max $p50 $p95 $p99"
}

prepare_cpu_values_mcpu() {
  local resp="$1"
  local pod="$2"

  jq -r --arg pod "$pod" '.data.result[] | select(.metric.pod == $pod) | .values[] | @tsv' <<<"$resp" |
    awk '
      NR == 1 {
        prev_t = $1
        prev_v = $2
        next
      }
      {
        dt = $1 - prev_t
        dv = $2 - prev_v
        if (dt > 0 && dv >= 0) {
          print (dv / dt) * 1000
        }
        prev_t = $1
        prev_v = $2
      }'
}

prepare_mem_values_mib() {
  local resp="$1"
  local pod="$2"

  jq -r --arg pod "$pod" '.data.result[] | select(.metric.pod == $pod) | .values[] | .[1]' <<<"$resp"
}

is_greater() {
  local a="$1"
  local b="$2"
  awk -v x="$a" -v y="$b" 'BEGIN{ exit !(x > y) }'
}

# ==============================
# Vérifications initiales
# ==============================
check_dependencies

echo "========================================"
echo " Kubernetes load test"
echo "========================================"
echo
echo "Namespace       : ${NAMESPACE}"
echo "Prometheus      : ${PROM_NAMESPACE}/${PROM_SERVICE}"
echo "Local Prometheus: http://127.0.0.1:${PROM_LOCAL_PORT}"
echo "Rates           : ${RATES[*]}"
echo "Warm-up         : ${WARMUP_SECONDS}s"
echo "Mesure          : ${MEASURE_SECONDS}s"
echo "Step Prometheus : ${PROM_STEP_SECONDS}s"
echo "Marge sécurité  : ${SAFETY_MARGIN_PERCENT}%"
echo

# ==============================
# 1. Port-forward Prometheus
# ==============================
echo "[1/6] Démarrage du port-forward Prometheus..."

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

  if ! curl -fsS "http://127.0.0.1:${PROM_LOCAL_PORT}/-/ready" >/dev/null; then
    echo "ERREUR : Prometheus n'est pas accessible."
    cat /tmp/prometheus-port-forward.log
    exit 1
  fi
else
  echo "Port-forward déjà actif, on le réutilise."
fi

echo "OK : Prometheus accessible."
echo

# ==============================
# 2. Vérification du service nginx
# ==============================
echo "[2/6] Vérification du service nginx..."

if ! kubectl -n "${NAMESPACE}" get svc nginx-service >/dev/null 2>&1; then
  echo "ERREUR : le service nginx-service n'existe pas dans le namespace ${NAMESPACE}"
  exit 1
fi

if ! kubectl -n "${NAMESPACE}" get endpoints nginx-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
  echo "ERREUR : le service nginx-service n'a aucun endpoint actif"
  exit 1
fi

echo "OK : Service nginx-service trouvé et endpoints actifs."
echo

# ==============================
# 3. Création du load-generator
# ==============================
echo "[3/6] Création du load-generator..."

# Enregistrer l'heure de début globale
START=$(date +%s)

kubectl -n "${NAMESPACE}" delete pod "${LOAD_POD}" \
  --ignore-not-found=true \
  --wait=true >/dev/null 2>&1 || true

LOAD_SCRIPT=$(cat <<'LOAD_EOF'
set -u

run_load() {
    rate="$1"
    total_duration="$2"
    warmup="$3"
    measure="$4"

    total_req=0
    error_req=0
    success_req=0

    results_file="/tmp/curl_results.$$"
    : > "${results_file}"

    stage_start=$(date +%s)
    echo "MARKER_STAGE_START_${rate} ${stage_start}"

    echo "Stage ${rate} req/s - warmup ${warmup}s + mesure ${measure}s"
    echo "========================================"

    # ---- Warm-up ----
    warm_start="${stage_start}"
    warm_end=$((warm_start + warmup))

    while [ "$(date +%s)" -lt "$warm_end" ]; do
        i=0
        while [ "$i" -lt "$rate" ]; do
            (
                if curl -s -o /dev/null --connect-timeout 1 --max-time 2 --fail \
                    "http://nginx-service:8080/hello"; then
                    echo "OK" >> "${results_file}"
                else
                    echo "FAIL" >> "${results_file}"
                fi
            ) &
            i=$((i + 1))
        done
        sleep 1
    done

    # ---- Début de la mesure réelle ----
    measure_start=$(date +%s)
    echo "MARKER_MEASURE_START_${rate} ${measure_start}"
    measure_end=$((stage_start + total_duration))

    while [ "$(date +%s)" -lt "$measure_end" ]; do
        i=0
        while [ "$i" -lt "$rate" ]; do
            (
                if curl -s -o /dev/null --connect-timeout 1 --max-time 2 --fail \
                    "http://nginx-service:8080/hello"; then
                    echo "OK" >> "${results_file}"
                else
                    echo "FAIL" >> "${results_file}"
                fi
            ) &
            i=$((i + 1))
        done
        sleep 1
    done

    # Attendre que toutes les requêtes en arrière-plan se terminent
    wait || true

    success_req=$(grep -c "OK" "${results_file}" 2>/dev/null || true)
    error_req=$(grep -c "FAIL" "${results_file}" 2>/dev/null || true)
    total_req=$((success_req + error_req))

    rm -f "${results_file}"

    echo
    echo "RESULTAT ${rate} req/s :"
    echo "  - Total requêtes : ${total_req}"
    echo "  - Erreurs        : ${error_req}"
    if [ "$total_req" -gt 0 ]; then
        echo "  - Taux de succès : $(( (total_req - error_req) * 100 / total_req ))%"
    else
        echo "  - Taux de succès : N/A (aucune requête)"
    fi

    echo "MARKER_STAGE_END_${rate} $(date +%s)"

    if [ "$error_req" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ---- Test de connectivité initial ----
echo "Test de connectivité initial..."
if ! curl -s -o /dev/null --connect-timeout 2 --max-time 3 "http://nginx-service:8080/hello"; then
    echo "ERREUR : Impossible de joindre nginx-service"
    exit 1
fi
echo "Connectivité OK"
echo

# ---- Exécution des paliers ----
for rate in 10 50 100 200 500; do
    run_load "$rate" 180 60 120 || exit 1
    echo
done

echo "========================================"
echo "LOAD TEST TERMINE"
echo "========================================"
LOAD_EOF
)

kubectl -n "${NAMESPACE}" run "${LOAD_POD}" \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --command -- sh -c "${LOAD_SCRIPT}"

# ==============================
# 4. Attente du démarrage
# ==============================
echo "[4/6] Attente du load-generator..."

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Running \
  "pod/${LOAD_POD}" \
  --timeout=60s

echo "OK : load-generator Running."
echo

# ==============================
# 5. Suivi des logs
# ==============================
echo "[5/6] Démarrage du suivi des logs..."

: > "${LOG_FILE}"

kubectl -n "${NAMESPACE}" logs -f "${LOAD_POD}" > "${LOG_FILE}" 2>&1 &
KUBECTL_LOGS_PID=$!

tail -n +1 -f "${LOG_FILE}" &
LOAD_LOG_PID=$!

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/${LOAD_POD}" \
  --timeout=20m

END=$(date +%s)

echo
echo "END = ${END}"
echo

# Arrêter les processus de log
kill "${LOAD_LOG_PID}" 2>/dev/null || true
kill "${KUBECTL_LOGS_PID}" 2>/dev/null || true
wait "${LOAD_LOG_PID}" 2>/dev/null || true
wait "${KUBECTL_LOGS_PID}" 2>/dev/null || true

# ==============================
# 6. Extraction des timestamps
# ==============================
for rate in "${RATES[@]}"; do
  start_line=$(grep -m1 "MARKER_STAGE_START_${rate}" "${LOG_FILE}" || true)
  measure_line=$(grep -m1 "MARKER_MEASURE_START_${rate}" "${LOG_FILE}" || true)
  end_line=$(grep -m1 "MARKER_STAGE_END_${rate}" "${LOG_FILE}" || true)

  [ -n "$start_line" ] && STAGE_START[$rate]=$(echo "$start_line" | awk '{print $NF}') || STAGE_START[$rate]=0
  [ -n "$measure_line" ] && MEASURE_START[$rate]=$(echo "$measure_line" | awk '{print $NF}') || MEASURE_START[$rate]=0
  [ -n "$end_line" ] && STAGE_END[$rate]=$(echo "$end_line" | awk '{print $NF}') || STAGE_END[$rate]=0
done

# ==============================
# 7. Analyse Prometheus
# ==============================
echo
echo "========================================"
echo " BILAN FINAL"
echo "========================================"
echo
echo "Début : $(date -d "@${START}")"
echo "Fin   : $(date -d "@${END}")"
echo

overall_worst_cpu_p99_mcpu=-1
overall_worst_cpu_pod=""
overall_worst_mem_p99_mib=-1
overall_worst_mem_pod=""

for rate in "${RATES[@]}"; do
  st="${STAGE_START[$rate]}"
  mt="${MEASURE_START[$rate]}"
  et="${STAGE_END[$rate]}"

  echo "=========================================="
  echo " Rate ${rate} req/s"
  echo "=========================================="

  if [ "$st" -le 0 ] || [ "$mt" -le 0 ] || [ "$et" -le 0 ]; then
    echo "  ERREUR : timestamps manquants pour ce palier"
    continue
  fi

  cpu_query="sum by (pod) (container_cpu_usage_seconds_total{namespace=\"${NAMESPACE}\",container=\"nginx\",image!=\"\"})"
  mem_query="sum by (pod) (container_memory_working_set_bytes{namespace=\"${NAMESPACE}\",container=\"nginx\",image!=\"\"}) / 1024 / 1024"

  resp_cpu=$(prom_query_range "$cpu_query" "$mt" "$et" "${PROM_STEP_SECONDS}")
  resp_mem=$(prom_query_range "$mem_query" "$mt" "$et" "${PROM_STEP_SECONDS}")

  pods_cpu=$(jq -r '.data.result[]?.metric.pod' <<<"$resp_cpu" | sort -u || true)
  pods_mem=$(jq -r '.data.result[]?.metric.pod' <<<"$resp_mem" | sort -u || true)
  pods=$( { echo "$pods_cpu"; echo "$pods_mem"; } | sort -u | sed '/^$/d' )

  if [ -z "$pods" ]; then
    echo "  Aucune métrique nginx trouvée pour ce palier"
    continue
  fi

  rate_worst_cpu_p99=-1
  rate_worst_cpu_pod=""
  rate_worst_mem_p99=-1
  rate_worst_mem_pod=""

  while IFS= read -r pod; do
    # ----- CPU -----
    cpu_vals_mcpu=$(prepare_cpu_values_mcpu "$resp_cpu" "$pod")
    read cpu_count cpu_max cpu_p50 cpu_p95 cpu_p99 <<<"$(compute_stats "$cpu_vals_mcpu")"

    # ----- Mémoire -----
    mem_vals_mib=$(prepare_mem_values_mib "$resp_mem" "$pod")
    read mem_count mem_max mem_p50 mem_p95 mem_p99 <<<"$(compute_stats "$mem_vals_mib")"

    printf "  pod %s\n" "$pod"
    printf "    CPU max %.1fm | p50 %.1fm | p95 %.1fm | p99 %.1fm (n=%d)\n" \
      "$cpu_max" "$cpu_p50" "$cpu_p95" "$cpu_p99" "$cpu_count"
    printf "    MEM max %.1fMi | p50 %.1fMi | p95 %.1fMi | p99 %.1fMi (n=%d)\n" \
      "$mem_max" "$mem_p50" "$mem_p95" "$mem_p99" "$mem_count"

    if [ "$cpu_count" -lt 3 ]; then
      echo "    ATTENTION : peu de points CPU pour ce pod"
    fi
    if [ "$mem_count" -lt 3 ]; then
      echo "    ATTENTION : peu de points mémoire pour ce pod"
    fi

    # Mise à jour pire pod du palier CPU
    if is_greater "$cpu_p99" "$rate_worst_cpu_p99"; then
      rate_worst_cpu_p99="$cpu_p99"
      rate_worst_cpu_pod="$pod"
    fi

    # Mise à jour pire pod du palier mémoire
    if is_greater "$mem_p99" "$rate_worst_mem_p99"; then
      rate_worst_mem_p99="$mem_p99"
      rate_worst_mem_pod="$pod"
    fi
  done <<< "$pods"

  echo
  echo "  Worst CPU p99 : ${rate_worst_cpu_pod} = ${rate_worst_cpu_p99} mCPU"
  echo "  Worst MEM p99 : ${rate_worst_mem_pod} = ${rate_worst_mem_p99} MiB"

  # Mise à jour pire global CPU
  if is_greater "$rate_worst_cpu_p99" "$overall_worst_cpu_p99_mcpu"; then
    overall_worst_cpu_p99_mcpu="$rate_worst_cpu_p99"
    overall_worst_cpu_pod="$rate_worst_cpu_pod"
  fi

  # Mise à jour pire global mémoire
  if is_greater "$rate_worst_mem_p99" "$overall_worst_mem_p99_mib"; then
    overall_worst_mem_p99_mib="$rate_worst_mem_p99"
    overall_worst_mem_pod="$rate_worst_mem_pod"
  fi

  echo
done

# ==============================
# 8. Rapport final de dimensionnement
# ==============================
echo
echo "=========================================="
echo " FINAL SIZING DATA"
echo "=========================================="
if [ -n "$overall_worst_cpu_pod" ]; then
  echo "Worst observed nginx CPU p99 : ${overall_worst_cpu_pod} = ${overall_worst_cpu_p99_mcpu} mCPU"
else
  echo "Worst observed nginx CPU p99 : aucune donnée"
fi

if [ -n "$overall_worst_mem_pod" ]; then
  echo "Worst observed nginx MEM p99 : ${overall_worst_mem_pod} = ${overall_worst_mem_p99_mib} MiB"
else
  echo "Worst observed nginx MEM p99 : aucune donnée"
fi

if [ -n "$overall_worst_cpu_pod" ] || [ -n "$overall_worst_mem_pod" ]; then
  rec_cpu=$(awk -v p99="$overall_worst_cpu_p99_mcpu" -v m="$SAFETY_MARGIN_PERCENT" 'BEGIN{printf "%.1f", p99 * (1 + m/100)}')
  rec_mem=$(awk -v p99="$overall_worst_mem_p99_mib" -v m="$SAFETY_MARGIN_PERCENT" 'BEGIN{printf "%.1f", p99 * (1 + m/100)}')

  echo
  echo "Marge de sécurité : ${SAFETY_MARGIN_PERCENT}%"
  echo "CPU recommandé :  p99 ${overall_worst_cpu_p99_mcpu} mCPU * 1.${SAFETY_MARGIN_PERCENT} = ${rec_cpu} mCPU"
  echo "MEM recommandé :  p99 ${overall_worst_mem_p99_mib} MiB * 1.${SAFETY_MARGIN_PERCENT} = ${rec_mem} MiB"
  echo
  echo "Suggestion pour un conteneur nginx :"
  echo "  requests.cpu    = $(printf '%.0f' "$rec_cpu")m"
  echo "  limits.cpu      = $(printf '%.0f' "$(awk -v r="$rec_cpu" 'BEGIN{print r*2}')")m"
  echo "  requests.memory = ${rec_mem}Mi"
  echo "  limits.memory   = $(awk -v r="$rec_mem" 'BEGIN{printf "%.0f", r*2}')Mi"
fi

echo
echo "========================================"
echo " TEST TERMINE"
echo "========================================"
