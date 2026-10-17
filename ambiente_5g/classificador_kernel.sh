#!/bin/bash
# =============================================================================
# run_experiment.sh
# Executa N iterações do experimento de classificação de tráfego eBPF/XDP.
#
# Para cada iteração:
#   1. Inicia os geradores de tráfego URLLC e eMBB no container b-ue
#   2. Inicia o classificador kernel (monitorjanela.py) no host
#   3. Inicia a coleta de CPU com mpstat no host
#   4. Aguarda o fim da duração do experimento
#   5. Encerra tudo e aguarda cooldown antes da próxima iteração
#
# Uso:
#   chmod +x run_experiment.sh
#   ./run_experiment.sh
# =============================================================================

# ------------------------------------------------------------------
# Parâmetros — ajuste conforme seu ambiente
# ------------------------------------------------------------------
N_ITER=30                          # número de iterações
TRAFFIC_DURATION=60               # duração do tráfego em segundos
COOLDOWN=30                       # tempo de espera entre iterações (s)
MPSTAT_INTERVAL=1                 # intervalo de amostragem do mpstat (s)

CONTAINER="b-ue"                  # nome do container Docker do UE
DST_IP="10.150.0.100"             # IP do Data Network
IAT_ALVO=0.007

CLASSIFIER_DIR="./pesquisa_galvao/kernel_class"

OUTPUT_DIR="./resultados_kernel"
# ------------------------------------------------------------------

MPSTAT_PID=""
CLASSIFIER_PID=""

mkdir -p "$OUTPUT_DIR"

# Criar um cgroup cpuset
sudo cgcreate -g cpuset:/classificador 2>/dev/null || true
sudo cgset -r cpuset.cpus=2,3 /classificador
sudo cgset -r cpuset.mems=0 /classificador

# ------------------------------------------------------------------
# Função de limpeza — chamada pelo trap no Ctrl+C ou saída do script
# ------------------------------------------------------------------
cleanup() {
    echo ""
    echo "[!!] Interrompido — encerrando processos..."

    docker exec "$CONTAINER" pkill -f urllc_generator.py 2>/dev/null
    docker exec "$CONTAINER" pkill -f embb_generator.py  2>/dev/null

    sudo pkill -f monitorjanela.py 2>/dev/null
    sleep 1
    sudo pkill -9 -f monitorjanela.py 2>/dev/null
    sudo cgdelete -g cpuset:/classificador 2>/dev/null || true

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

    RESULT_CSV="$OUTPUT_DIR/resultado_kernel_${i}.csv"
    MPSTAT_TXT="$OUTPUT_DIR/mpstat_kernel_${i}.txt"

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
    # 2. Inicia o classificador no host
    # ------------------------------------------------------------------
    echo "[2/4] Iniciando classificador kernel..."

    cd "$CLASSIFIER_DIR" || { echo "[ERRO] Diretorio $CLASSIFIER_DIR nao encontrado."; exit 1; }

    sudo LD_LIBRARY_PATH=/opt/bcc/lib \
         PYTHONPATH=/opt/bcc/lib/python3/dist-packages/bcc-0.36.1+a14e204d-py3.10.egg \
         cgexec -g cpuset:/classificador python3 monitorjanela.py > "$OLDPWD/$RESULT_CSV" 2>/dev/null &
    CLASSIFIER_PID=$!

    cd - > /dev/null

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

    sudo pkill -f monitorjanela.py 2>/dev/null
    sleep 1
    sudo pkill -9 -f monitorjanela.py 2>/dev/null
    wait "$CLASSIFIER_PID" 2>/dev/null

    if kill -0 "$MPSTAT_PID" 2>/dev/null; then
        kill "$MPSTAT_PID" 2>/dev/null
        wait "$MPSTAT_PID" 2>/dev/null
    fi

    MPSTAT_PID=""
    CLASSIFIER_PID=""

    echo "[OK] Iteracao $i concluida."
    echo "[OK] CSV : resultado_kernel_${i}.csv"
    echo "[OK] CPU : mpstat_kernel_${i}.txt"

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
