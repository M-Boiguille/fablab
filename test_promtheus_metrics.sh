#!/usr/bin/env bash

set -u

NAMESPACE="dev"
LOAD_POD="load-generator"

echo "============================================================"
echo "        TEST DE CHARGE NGINX + PROMETHEUS"
echo "============================================================"
echo
echo "Namespace : $NAMESPACE"
echo "Target    : http://nginx-service:8080/hello"
echo
echo "Charge :"
echo "  0-8 s   : 10 req/s"
echo "  8-16 s  : 50 req/s"
echo "  16-24 s : 100 req/s"
echo "  24-32 s : 200 req/s"
echo "  32-40 s : 500 req/s"
echo

# ------------------------------------------------------------
# Vérification Service
# ------------------------------------------------------------

echo "[1/4] Vérification du Service nginx..."

kubectl -n "$NAMESPACE" get svc nginx-service >/dev/null 2>&1 || {
  echo "ERREUR : Service nginx-service introuvable"
  kubectl -n "$NAMESPACE" get svc
  exit 1
}

echo "OK"

# ------------------------------------------------------------
# Recherche Prometheus
# ------------------------------------------------------------

echo
echo "[2/4] Recherche du pod Prometheus..."

PROM_POD=$(kubectl -n tools get pods \
  -l app=prometheus \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$PROM_POD" ]; then
  echo "ERREUR : pod Prometheus introuvable"
  kubectl -n tools get pods
  exit 1
fi

echo "Prometheus : $PROM_POD"

# ------------------------------------------------------------
# Nettoyage
# ------------------------------------------------------------

echo
echo "[3/4] Nettoyage d'un éventuel ancien load-generator..."

kubectl -n "$NAMESPACE" delete pod "$LOAD_POD" \
  --ignore-not-found --wait=true >/dev/null 2>&1

# ------------------------------------------------------------
# Création load-generator
# ------------------------------------------------------------

echo
echo "[4/4] Création du pod de charge..."
echo
echo "IMPORTANT : aucun resources.requests / resources.limits"
echo "=> pod BestEffort."
echo

kubectl -n "$NAMESPACE" run "$LOAD_POD" \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --command -- sh -c '
        set -u

        TARGET="http://nginx-service:8080/hello"

        echo "============================================================"
        echo " LOAD GENERATOR"
        echo "============================================================"
        echo "Target : $TARGET"
        echo

        run_load() {
            RATE="$1"
            DURATION="$2"

            echo
            echo "############################################################"
            echo "# DEBUT ETAPE : ${RATE} req/s"
            echo "# DUREE       : ${DURATION}s"
            echo "############################################################"

            START=$(date +%s)
            END=$((START + DURATION))

            TOTAL=0
            ERRORS=0
            LAST_LOG=$START

            while [ "$(date +%s)" -lt "$END" ]; do

                for i in $(seq 1 "$RATE"); do
                    (
                        curl -s \
                             -o /dev/null \
                             --connect-timeout 1 \
                             --max-time 2 \
                             --fail \
                             "$TARGET"
                    ) &

                    TOTAL=$((TOTAL + 1))
                done

                for PID in $(jobs -p); do
                    wait "$PID" || ERRORS=$((ERRORS + 1))
                done

                NOW=$(date +%s)

                if [ $((NOW - LAST_LOG)) -ge 2 ]; then
                    ELAPSED=$((NOW - START))
                    REMAINING=$((END - NOW))

                    echo "[$(date "+%H:%M:%S")] rate=${RATE}/s elapsed=${ELAPSED}s remaining=${REMAINING}s total=${TOTAL} errors=${ERRORS}"

                    LAST_LOG=$NOW
                fi

                sleep 1
            done

            echo
            echo "############################################################"
            echo "# FIN ETAPE : ${RATE} req/s"
            echo "# Requêtes : ${TOTAL}"
            echo "# Erreurs  : ${ERRORS}"
            echo "############################################################"

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
        echo "============================================================"
        echo " LOAD TEST TERMINE AVEC SUCCÈS"
        echo "============================================================"

        exit 0
    '

echo
echo "Pod créé."

# ------------------------------------------------------------
# Attente démarrage
# ------------------------------------------------------------

echo
echo "Attente du démarrage du load-generator..."

kubectl -n "$NAMESPACE" wait \
  --for=condition=Ready \
  pod/"$LOAD_POD" \
  --timeout=60s >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Logs du générateur UNIQUEMENT
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                LOGS DU LOAD-GENERATOR"
echo "============================================================"
echo
echo "Ctrl+C arrête uniquement l'affichage."
echo "Le test continue dans Kubernetes."
echo

kubectl -n "$NAMESPACE" logs -f "$LOAD_POD" 2>&1 |
  sed 's/^/[LOAD] /' &

LOAD_LOG_PID=$!

# ------------------------------------------------------------
# Attente réelle de fin
# ------------------------------------------------------------

echo
echo "Test en cours..."
echo
echo "Attente de la fin du load test..."

kubectl -n "$NAMESPACE" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/"$LOAD_POD" \
  --timeout=12m >/dev/null 2>&1

WAIT_RESULT=$?

# ------------------------------------------------------------
# Arrêt affichage logs
# ------------------------------------------------------------

kill "$LOAD_LOG_PID" 2>/dev/null || true
wait "$LOAD_LOG_PID" 2>/dev/null || true

# ------------------------------------------------------------
# État réel du Pod
# ------------------------------------------------------------

PHASE=$(kubectl -n "$NAMESPACE" get pod "$LOAD_POD" \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

echo
echo "============================================================"
echo "                 TEST TERMINE"
echo "============================================================"
echo
echo "Pod phase : $PHASE"
echo

kubectl -n "$NAMESPACE" get pod "$LOAD_POD" -o wide 2>/dev/null || true

echo
echo "Derniers logs du générateur :"
echo

kubectl -n "$NAMESPACE" logs "$LOAD_POD" \
  --tail=30 2>/dev/null || true

echo

if [ "$PHASE" = "Succeeded" ]; then
  echo "✅ LOAD TEST : SUCCÈS"
  exit 0
elif [ "$PHASE" = "Failed" ]; then
  echo "❌ LOAD TEST : ÉCHEC"
  exit 1
else
  echo "⚠️ LOAD TEST : ÉTAT INCONNU ($PHASE)"
  exit 2
fi
