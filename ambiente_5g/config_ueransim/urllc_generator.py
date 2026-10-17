#!/usr/bin/env python3
"""
Gerador de tráfego URLLC com socket UDP
====================================
Simula tráfego URLLC (Ultra-Reliable Low Latency Communication),
inspirado no modelo de controle de braço robótico descrito em
Kalør et al. (2018) e referenciado no artigo eBPF/XDP (Galvão et al., 2026).

Características do tráfego gerado:
- Pacotes pequenos e periódicos (padrão determinístico)
- IAT (Inter-Arrival Time) baixo e regular (~ 1 ms)
- Protocolo UDP
- Payload fixo de 128 bytes (conforme Tabela I de Kalør et al.)

Uso:
    python3 urllc_generator.py --dst <IP_DESTINO>

Exemplo:
    python3 urllc_generator.py --dst 10.150.0.100
"""

import argparse
import socket
import time


# ------------------------------------------------------------------
# Parâmetros padrão — ajuste conforme seu ambiente
# ------------------------------------------------------------------
DEFAULT_DST_IP   = "10.150.0.100"
DEFAULT_DST_PORT = 9001
DEFAULT_SRC_PORT = 10001
DEFAULT_IFACE    = "uesimtun0"    # mantido por documentação, não usado pelo socket
DEFAULT_DURATION = 60
DEFAULT_IAT_S    = 0.008
DEFAULT_PAYLOAD  = 128
# ------------------------------------------------------------------


def run(dst_ip: str, dst_port: int, src_port: int, iface: str,
        duration: float, iat: float, payload_size: int):
    """Loop principal de envio com controle de IAT."""

    payload = b"U" * payload_size  # 'U' de URLLC — facilita inspeção

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("", src_port))

    print(f"[URLLC] Iniciando envio para {dst_ip}:{dst_port}")
    print(f"        Interface : {iface}")
    print(f"        IAT alvo  : {iat * 1000:.2f} ms")
    print(f"        Payload   : {payload_size} bytes")
    print(f"        Duração   : {duration} s")
    print(f"        Pressione Ctrl+C para interromper.\n")

    sent    = 0
    t_start = time.perf_counter()

    try:
        while True:
            elapsed = time.perf_counter() - t_start

            if elapsed >= duration:
                break

            time.sleep(iat)
            sock.sendto(payload, (dst_ip, dst_port))
            sent += 1

            if sent % 1000 == 0:
                print(f"  [{elapsed:.1f}s] Pacotes enviados: {sent}")

    except KeyboardInterrupt:
        print("\n[URLLC] Interrompido pelo usuário.")
    finally:
        sock.close()

    total_time = time.perf_counter() - t_start
    real_iat   = (total_time / sent * 1000) if sent > 0 else 0

    print(f"\n[URLLC] Resumo:")
    print(f"  Pacotes enviados : {sent}")
    print(f"  Tempo total      : {total_time:.2f} s")
    print(f"  IAT médio real   : {real_iat:.3f} ms  (alvo: {iat*1000:.2f} ms)")


def parse_args():
    p = argparse.ArgumentParser(
        description="Gerador de tráfego URLLC com socket UDP"
    )
    p.add_argument("--dst",      default=DEFAULT_DST_IP,
                   help=f"IP destino (padrão: {DEFAULT_DST_IP})")
    p.add_argument("--dport",    type=int, default=DEFAULT_DST_PORT,
                   help=f"Porta UDP destino (padrão: {DEFAULT_DST_PORT})")
    p.add_argument("--sport",    type=int, default=DEFAULT_SRC_PORT,
                   help=f"Porta UDP origem (padrão: {DEFAULT_SRC_PORT})")
    p.add_argument("--iface",    default=DEFAULT_IFACE,
                   help=f"Interface de rede (padrão: {DEFAULT_IFACE})")
    p.add_argument("--duration", type=float, default=DEFAULT_DURATION,
                   help=f"Duração em segundos (padrão: {DEFAULT_DURATION})")
    p.add_argument("--iat",      type=float, default=DEFAULT_IAT_S,
                   help=f"IAT em segundos (padrão: {DEFAULT_IAT_S} = 1 ms)")
    p.add_argument("--payload",  type=int, default=DEFAULT_PAYLOAD,
                   help=f"Tamanho do payload em bytes (padrão: {DEFAULT_PAYLOAD})")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(
        dst_ip       = args.dst,
        dst_port     = args.dport,
        src_port     = args.sport,
        iface        = args.iface,
        duration     = args.duration,
        iat          = args.iat,
        payload_size = args.payload,
    )
