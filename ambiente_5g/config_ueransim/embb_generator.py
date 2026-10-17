#!/usr/bin/env python3
"""
Gerador de tráfego eMBB com socket UDP
====================================
Simula tráfego eMBB (Enhanced Mobile Broadband), inspirado no modelo
de AR stream descrito em Kalør et al. (2018) e referenciado no artigo
eBPF/XDP (Galvão et al., 2026).

Características do tráfego gerado:
- Rajadas periódicas de pacotes grandes (simula chunks de vídeo)
- IAT variável: pequeno dentro da rajada, maior entre rajadas
- Protocolo UDP via socket puro

Portas (distintas do URLLC para garantir fluxos separados):
- Porta destino : 9002  (URLLC usa 9001)
- Porta origem  : 10002 (URLLC usa 10001)

Uso:
    python3 embb_generator.py --dst <IP_DESTINO>

Exemplo:
    python3 embb_generator.py --dst 10.150.0.100
"""

import argparse
import socket
import time


# ------------------------------------------------------------------
# Parâmetros padrão
# ------------------------------------------------------------------
DEFAULT_DST_IP          = "10.150.0.100"
DEFAULT_DST_PORT        = 9002
DEFAULT_SRC_PORT        = 10002
DEFAULT_IFACE           = "uesimtun0"    # mantido por documentação, não usado pelo socket
DEFAULT_DURATION        = 60
DEFAULT_BURST_INTERVAL  = 0.020
DEFAULT_BURST_PACKETS   = 20
DEFAULT_PACKET_SIZE     = 1000
DEFAULT_IAT_INTRA_BURST = 0.0005
# ------------------------------------------------------------------


def precise_sleep(duration: float):
    """Sleep híbrido: dorme a maior parte e faz busy-wait no último
    0,5 ms para melhorar a precisão sem consumir CPU o tempo todo."""
    t_end = time.perf_counter() + duration
    slack = duration - 0.0005
    if slack > 0:
        time.sleep(slack)
    while time.perf_counter() < t_end:
        pass


def run(dst_ip: str, dst_port: int, src_port: int, iface: str,
        duration: float, burst_interval: float, burst_packets: int,
        packet_size: int, iat_intra: float):
    """Loop principal: envia rajadas periódicas para simular streaming."""

    payload = b"E" * packet_size  # 'E' de eMBB

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("", src_port))

    bytes_per_burst = burst_packets * packet_size
    throughput_kbps = (bytes_per_burst * 8) / burst_interval / 1000

    print(f"[eMBB] Iniciando envio para {dst_ip}:{dst_port}")
    print(f"       Interface           : {iface}")
    print(f"       Porta origem        : {src_port}")
    print(f"       Intervalo de rajada : {burst_interval * 1000:.1f} ms")
    print(f"       Pacotes por rajada  : {burst_packets}")
    print(f"       Tamanho do pacote   : {packet_size} bytes")
    print(f"       IAT intra-rajada    : {iat_intra * 1000:.2f} ms")
    print(f"       Throughput alvo     : ~{throughput_kbps:.0f} kbps")
    print(f"       Duração             : {duration} s")
    print(f"       Pressione Ctrl+C para interromper.\n")

    sent         = 0
    bursts       = 0
    t_start      = time.perf_counter()
    t_next_burst = t_start

    try:
        while True:
            if time.perf_counter() - t_start >= duration:
                break

            wait = t_next_burst - time.perf_counter()
            if wait > 0:
                precise_sleep(wait)

            # Envia a rajada
            for i in range(burst_packets):
                t_pkt = time.perf_counter()
                sock.sendto(payload, (dst_ip, dst_port))
                sent += 1

                if i < burst_packets - 1:
                    elapsed_send = time.perf_counter() - t_pkt
                    remaining = iat_intra - elapsed_send
                    if remaining > 0:
                        precise_sleep(remaining)

            bursts       += 1
            t_next_burst += burst_interval

            if bursts % 50 == 0:
                elapsed = time.perf_counter() - t_start
                print(f"  [{elapsed:.1f}s] Rajadas: {bursts} | Pacotes: {sent}")

    except KeyboardInterrupt:
        print("\n[eMBB] Interrompido pelo usuário.")
    finally:
        sock.close()

    total_time = time.perf_counter() - t_start
    real_rate  = (sent * packet_size * 8) / total_time / 1000 if total_time > 0 else 0

    print(f"\n[eMBB] Resumo:")
    print(f"  Rajadas enviadas  : {bursts}")
    print(f"  Pacotes enviados  : {sent}")
    print(f"  Tempo total       : {total_time:.2f} s")
    print(f"  Throughput real   : {real_rate:.0f} kbps")


def parse_args():
    p = argparse.ArgumentParser(
        description="Gerador de tráfego eMBB com socket UDP"
    )
    p.add_argument("--dst",            default=DEFAULT_DST_IP,
                   help=f"IP destino (padrão: {DEFAULT_DST_IP})")
    p.add_argument("--dport",          type=int, default=DEFAULT_DST_PORT,
                   help=f"Porta UDP destino (padrão: {DEFAULT_DST_PORT})")
    p.add_argument("--sport",          type=int, default=DEFAULT_SRC_PORT,
                   help=f"Porta UDP origem (padrão: {DEFAULT_SRC_PORT})")
    p.add_argument("--iface",          default=DEFAULT_IFACE,
                   help=f"Interface de rede (padrão: {DEFAULT_IFACE})")
    p.add_argument("--duration",       type=float, default=DEFAULT_DURATION,
                   help=f"Duração em segundos (padrão: {DEFAULT_DURATION})")
    p.add_argument("--burst-interval", type=float, default=DEFAULT_BURST_INTERVAL,
                   help=f"Intervalo entre rajadas em s (padrão: {DEFAULT_BURST_INTERVAL})")
    p.add_argument("--burst-packets",  type=int,   default=DEFAULT_BURST_PACKETS,
                   help=f"Pacotes por rajada (padrão: {DEFAULT_BURST_PACKETS})")
    p.add_argument("--pkt-size",       type=int,   default=DEFAULT_PACKET_SIZE,
                   help=f"Bytes por pacote (padrão: {DEFAULT_PACKET_SIZE})")
    p.add_argument("--iat-intra",      type=float, default=DEFAULT_IAT_INTRA_BURST,
                   help=f"IAT intra-rajada em s (padrão: {DEFAULT_IAT_INTRA_BURST})")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(
        dst_ip         = args.dst,
        dst_port       = args.dport,
        src_port       = args.sport,
        iface          = args.iface,
        duration       = args.duration,
        burst_interval = args.burst_interval,
        burst_packets  = args.burst_packets,
        packet_size    = args.pkt_size,
        iat_intra      = args.iat_intra,
    )
