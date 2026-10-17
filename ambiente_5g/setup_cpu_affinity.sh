#!/bin/bash
# setup_cpu_affinity.sh

set -euo pipefail

# ============================================================================
# CONFIGURAÇÃO
# ============================================================================

# CPUs reservadas para a UPF
UPF_CPUS="2,3"
UPF_CPU_MASK="c"

# CPUs para todas as demais interfaces (0,1,4,5,6,7)
OTHER_CPU_MASK="f3"
OTHER_CPUS="0,1,4,5,6,7"

# Containers e interfaces relevantes para o plano de dados
UPF_CONTAINER="b-upf"
GNB_CONTAINER="b-gnb"

# Interfaces do container UPF que carregam tráfego GTP-U
N3_IFACE="eth2"
N6_IFACE="eth1"
UPF_IFACES=("${N3_IFACE}" "${N6_IFACE}")

# Interface do gNB na rede N3 — veth no host recebe o XDP do classificador (uplink)
GNB_N3_IFACE="eth1"

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

find_host_veth() {
    local container=$1
    local iface=$2

    local iflink
    iflink=$(docker exec "${container}" \
             cat /sys/class/net/${iface}/iflink 2>/dev/null) || {
        log "ERRO: não encontrou iflink de ${iface} em ${container}"
        return 1
    }

    local veth
    veth=$(ip link show \
           | awk -F': ' "/^[[:space:]]*${iflink}:/{print \$2}" \
           | cut -d'@' -f1) || true

    if [ -z "${veth}" ]; then
        log "ERRO: não encontrou veth com ifindex ${iflink} no host"
        log "      Verifique se o container ${container} está rodando"
        return 1
    fi

    echo "${veth}"
}

set_rps() {
    local iface=$1
    local mask=$2

    local rps_dir="/sys/class/net/${iface}/queues"
    if [ ! -d "${rps_dir}" ]; then
        log "AVISO: diretório de filas não encontrado para ${iface}"
        return 1
    fi

    local count=0
    for queue_dir in "${rps_dir}"/rx-*; do
        if [ -f "${queue_dir}/rps_cpus" ]; then
            echo "${mask}" > "${queue_dir}/rps_cpus"
            count=$((count + 1))
        fi
    done

    if [ "${count}" -eq 0 ]; then
        log "AVISO: nenhuma fila rx encontrada em ${iface}"
        return 1
    fi

    log "RPS configurado em ${iface} (${count} fila(s)) → máscara 0x${mask}"
}

# ============================================================================
# PASSO 1: Desabilita irqbalance
# ============================================================================

log ""
log "=== Desabilitando irqbalance ==="

if systemctl is-active --quiet irqbalance; then
    systemctl stop irqbalance
    systemctl disable irqbalance
    log "irqbalance parado e desabilitado"
else
    log "irqbalance já estava inativo"
fi

# ============================================================================
# PASSO 2: Configura RPS nas interfaces veth da UPF → CPUs 2,3
# ============================================================================

log ""
log "=== Configurando RPS nas interfaces veth da UPF ==="
log "    UPF CPUs: ${UPF_CPUS} (máscara 0x${UPF_CPU_MASK})"

# Coleta os ifindices das veths da UPF para excluí-las no passo 3
UPF_VETH_NAMES=()

for iface in "${UPF_IFACES[@]}"; do
    log ""
    log "--- Interface ${iface} do container ${UPF_CONTAINER} ---"

    veth=$(find_host_veth "${UPF_CONTAINER}" "${iface}") || continue

    log "  Interface no container : ${iface}"
    log "  Interface par no host  : ${veth}"

    set_rps "${veth}" "${UPF_CPU_MASK}" || true
    UPF_VETH_NAMES+=("${veth}")
done

# ============================================================================
# PASSO 2b: Configura RPS na veth N3 do gNB → CPUs 2,3
# (o XDP do classificador é anexado nessa veth para capturar uplink)
# ============================================================================

log ""
log "=== Configurando RPS na veth N3 do gNB ==="
log "    CPUs: ${UPF_CPUS} (máscara 0x${UPF_CPU_MASK})"
log ""
log "--- Interface ${GNB_N3_IFACE} do container ${GNB_CONTAINER} ---"

gnb_veth=$(find_host_veth "${GNB_CONTAINER}" "${GNB_N3_IFACE}") || true

if [ -n "${gnb_veth}" ]; then
    log "  Interface no container : ${GNB_N3_IFACE}"
    log "  Interface par no host  : ${gnb_veth}"
    set_rps "${gnb_veth}" "${UPF_CPU_MASK}" || true
    UPF_VETH_NAMES+=("${gnb_veth}")
else
    log "AVISO: não foi possível identificar a veth N3 do gNB"
fi

# ============================================================================
# PASSO 3: Configura RPS em todas as demais interfaces → CPUs 0,1,4,5,6,7
# ============================================================================

log ""
log "=== Configurando RPS nas demais interfaces do host ==="
log "    Outras CPUs: ${OTHER_CPUS} (máscara 0x${OTHER_CPU_MASK})"

for iface in $(ip link show | grep -oP '^\d+: \K[^:@]+' | grep -v lo); do
    # Pula interfaces sem diretório de filas (ex: bridges sem RPS)
    if [ ! -d "/sys/class/net/${iface}/queues" ]; then
        continue
    fi

    # Pula as veths da UPF e do gNB N3
    skip=0
    for reserved_veth in "${UPF_VETH_NAMES[@]}"; do
        if [ "${iface}" = "${reserved_veth}" ]; then
            skip=1
            break
        fi
    done

    if [ "${skip}" -eq 1 ]; then
        log "  Pulando ${iface} (veth reservada para CPUs 2,3)"
        continue
    fi

    set_rps "${iface}" "${OTHER_CPU_MASK}" || true
done

# ============================================================================
# PASSO 4: Mostra o estado atual para verificação
# ============================================================================

log ""
log "=== Estado atual do RPS em todas as interfaces ==="

for iface in $(ip link show | grep -oP '^\d+: \K[^:@]+' | grep -v lo); do
    for queue_dir in /sys/class/net/${iface}/queues/rx-*; do
        if [ -f "${queue_dir}/rps_cpus" ]; then
            echo "  ${iface} $(basename ${queue_dir})/rps_cpus = $(cat ${queue_dir}/rps_cpus)"
        fi
    done
done

# ============================================================================
# PASSO 5: Mostra resumo de alocação de CPUs dos containers
# ============================================================================

log ""
log "=== CPUs alocadas por container (cpuset) ==="
for container in b-mongodb b-5gc-amf b-5gc-smf b-5gc-nrf b-5gc-scp \
                 b-5gc-udr b-5gc-udm b-5gc-ausf b-5gc-pcf b-5gc-nssf \
                 b-upf b-dn b-gnb b-ue; do
    cpuset=$(docker inspect --format '{{.HostConfig.CpusetCpus}}' \
             "${container}" 2>/dev/null) || cpuset="(não encontrado)"
    printf "  %-20s → CPUs: %s\n" "${container}" "${cpuset:-sem restrição}"
done

log ""
log "PARA REVERTER (reabilitar irqbalance):"
log "  sudo systemctl enable --now irqbalance"
