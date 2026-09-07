#!/bin/bash

set -u

NAMESPACE="dev"
LOAD_POD="load-generator"

PROM_NAMESPACE="tools"
PROM_SERVICE="prometheus"
PROM_LOCAL_PORT="9090"
PROM_REMOTE_PORT="9090"

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
# 3. Création du load generator
# --------------------------------------------------

echo "[3/6] Création du load-generator..."

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

    for ((sec=0; sec<DURATION; sec++)); do
        # Lancer RATE requêtes en parallèle
        for ((i=0; i<RATE; i++)); do
            (
                if curl -s \
                    -o /dev/null \
                    --connect-timeout 1 \
                    --max-time 2 \
                    --fail \
                    "http://nginx-service:8080/hello"; then
                    echo "OK" >> /tmp/curl_results_$$.log
                else
                    echo "FAIL" >> /tmp/curl_results_$$.log
                fi
            ) &
        done

        # Attendre que toutes les requêtes soient terminées
        wait || true

        # Compter les résultats
        OK_COUNT=$(grep -c "OK" /tmp/curl_results_$$.log 2>/dev/null || echo 0)
        FAIL_COUNT=$(grep -c "FAIL" /tmp/curl_results_$$.log 2>/dev/null || echo 0)

        TOTAL=$((TOTAL + OK_COUNT))
        ERRORS=$((ERRORS + FAIL_COUNT))

        # Nettoyer le fichier temporaire
        rm -f /tmp/curl_results_$$.log

        echo "  - Seconde $((sec+1)) : ${OK_COUNT} OK, ${FAIL_COUNT} erreurs"
    done

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
        return 1
    fi

    echo "SUCCÈS : ${TOTAL} requêtes, 0 erreur"
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
    run_load "$RATE" 8 || exit 1
    echo
done

echo
echo "========================================"
echo "LOAD TEST TERMINE"
echo "========================================"
'

# --------------------------------------------------
# 4. Attente Ready
# --------------------------------------------------

echo "[4/6] Attente du load-generator..."

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Running \
  "pod/${LOAD_POD}" \
  --timeout=60s

echo "OK : load-generator Running."
echo

# --------------------------------------------------
# 5. START + logs
# --------------------------------------------------

echo "[5/6] Démarrage de la mesure..."

START=$(date +%s)

echo "START = ${START}"
echo

# Afficher les logs du load-generator en temps réel
echo "=== Logs du load-generator ==="
kubectl -n "${NAMESPACE}" logs -f "${LOAD_POD}" 2>&1 &
LOAD_LOG_PID=$!

# --------------------------------------------------
# 6. Attente de la fin du test
# --------------------------------------------------

echo "[6/6] Test en cours..."
echo "Le test va durer environ $((${#RATES[@]} * DURATION)) secondes..."
echo

kubectl -n "${NAMESPACE}" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/${LOAD_POD}" \
  --timeout=15m

END=$(date +%s)

echo
echo "END = ${END}"
echo

# Arrêter le suivi des logs
if [ -n "${LOAD_LOG_PID}" ]; then
    kill "${LOAD_LOG_PID}" 2>/dev/null || true
    wait "${LOAD_LOG_PID}" 2>/dev/null || true
    LOAD_LOG_PID=""
fi

# Bilan final
echo
echo "========================================"
echo " BILAN FINAL"
echo "========================================"
echo
echo "Début : $(date -d "@${START}")"
echo "Fin   : $(date -d "@${END}")"
echo

# Afficher une dernière fois les ressources
echo "=== Ressources finales ==="
kubectl top pods -n "${NAMESPACE}" --sort-by=cpu 2>/dev/null || \
    echo "kubectl top indisponible (metrics-server ?)"

echo
echo "========================================"
echo " TEST TERMINE"
echo "========================================"
