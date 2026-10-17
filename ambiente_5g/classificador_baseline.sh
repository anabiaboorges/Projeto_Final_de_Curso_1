#!/bin/bash
# ------------------------------------------------------------------
# Parâmetros — ajuste conforme seu ambiente
# ------------------------------------------------------------------
N_ITER=3                         # número de iterações
TRAFFIC_DURATION=60               # duração do tráfego em segundos
COOLDOWN=30                       # tempo de espera entre iterações (s)
MPSTAT_INTERVAL=1                 # intervalo de amostragem do mpstat (s)

CONTAINER="b-ue"                  # nome do container Docker do UE
DST_IP="10.150.0.100"             # IP do Data Network
IAT_ALVO=0.007

OUTPUT_DIR="./resultados_baseline"
# ------------------------------------------------------------------

MPSTAT_PID=""
CLASSIFIER_PID=""

mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------
# Função de limpeza — chamada pelo trap no Ctrl+C ou saída do script
# ------------------------------------------------------------------
cleanup() {
    echo ""
    echo "[!!] Interrompido — encerrando processos..."

    docker exec "$CONTAINER" pkill -f urllc_generator.py 2>/dev/null
    docker exec "$CONTAINER" pkill -f embb_generator.py  2>/dev/null

    if [ -n "$MPSTAT_PID" ]; then
        kill "$MPSTAT_PID" 2>/dev/null
        wait "$MPSTAT_PID" 2>/dev/null
    fi

    echo "[!!] Processos encerrados. Saindo."
    exit 1
}

trap cleanup SIGINT SIGTERM

# ------------------------------------------------------------------

echo "=============================================="
echo " Experimento de classificacao eBPF/XDP"
echo " Iteracoes  : $N_ITER"
echo " Duracao    : ${TRAFFIC_DURATION}s por iteracao"
echo " Cooldown   : ${COOLDOWN}s entre iteracoes"
echo " Saida      : $OUTPUT_DIR"
echo "=============================================="
echo ""

for i in $(seq 1 $N_ITER); do
    echo "----------------------------------------------"
    echo " ITERACAO $i / $N_ITER  --  $(date '+%H:%M:%S')"
    echo "----------------------------------------------"

    RESULT_CSV="$OUTPUT_DIR/resultado_baseline_${i}.csv"
    MPSTAT_TXT="$OUTPUT_DIR/mpstat_baseline_${i}.txt"

    # ------------------------------------------------------------------
    # 1. Inicia os geradores de tráfego no container
    # ------------------------------------------------------------------
    echo "[1/4] Iniciando trafego no container $CONTAINER..."

    docker exec -d "$CONTAINER" \
        python3 /ueransim/build/urllc_generator.py \
            --dst "$DST_IP" \
            --iat "$IAT_ALVO" \
            --duration "$TRAFFIC_DURATION"

    docker exec -d "$CONTAINER" \
        python3 /ueransim/build/embb_generator.py \
            --dst "$DST_IP" \
            --duration "$TRAFFIC_DURATION"

    docker exec -d "$CONTAINER" \
        python3 /ueransim/build/urllc_generator.py \
            --dst "$DST_IP" \
            --iat 0.009 \
            --dport 9003 \
            --sport 10003 \
            --duration "$TRAFFIC_DURATION"

    docker exec -d "$CONTAINER" \
        python3 /ueransim/build/urllc_generator.py \
            --dst "$DST_IP" \
            --iat 0.006 \
            --dport 9004 \
            --sport 10004 \
            --duration "$TRAFFIC_DURATION"

    # Pequena pausa para o tráfego estabilizar antes de iniciar a coleta
    sleep 2

    # ------------------------------------------------------------------
    # 3. Inicia o mpstat no host
    # ------------------------------------------------------------------
    echo "[3/4] Iniciando coleta de CPU (mpstat)..."

    MPSTAT_COUNT=$(( TRAFFIC_DURATION - 2 ))
    mpstat -P ALL $MPSTAT_INTERVAL $MPSTAT_COUNT > "$MPSTAT_TXT" &
    MPSTAT_PID=$!

    # ------------------------------------------------------------------
    # 4. Aguarda o fim da duração do tráfego
    # ------------------------------------------------------------------
    echo "[4/4] Aguardando ${TRAFFIC_DURATION}s..."
    sleep "$TRAFFIC_DURATION"

    # ------------------------------------------------------------------
    # 5. Encerra todos os processos
    # ------------------------------------------------------------------
    echo "Encerrando processos..."

    docker exec "$CONTAINER" pkill -f urllc_generator.py 2>/dev/null
    docker exec "$CONTAINER" pkill -f embb_generator.py  2>/dev/null

    if kill -0 "$MPSTAT_PID" 2>/dev/null; then
        kill "$MPSTAT_PID" 2>/dev/null
        wait "$MPSTAT_PID" 2>/dev/null
    fi

    MPSTAT_PID=""

    echo "[OK] Iteracao $i concluida."
    echo "[OK] CSV : resultado_baseline_${i}.csv"
    echo "[OK] CPU : mpstat_baseline_${i}.txt"

    # ------------------------------------------------------------------
    # 6. Cooldown (exceto após a última iteração)
    # ------------------------------------------------------------------
    if [ "$i" -lt "$N_ITER" ]; then
        echo "[..] Cooldown ${COOLDOWN}s..."
        sleep "$COOLDOWN"
    fi

    echo ""
done

echo "=============================================="
echo " Experimento concluido -- $(date '+%H:%M:%S')"
echo " Resultados salvos em: $OUTPUT_DIR"
echo "=============================================="
