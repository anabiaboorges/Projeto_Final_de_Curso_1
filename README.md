# Projeto Final de Curso 1: monitoramento de tráfego 5G com eBPF

Projeto Final de Curso 1 (Engenharia de Computação, EMC/UFG).
Discentes: Ana Beatriz Borges Cordeiro e Bianca Pereira de Carvalho · Orientador: Prof. Flávio Geraldo Coelho Rocha.

Este repositório guarda o **ambiente experimental do PFC 1 exatamente como estava na VM** em 17/10/2026, antes de qualquer mudança para o PFC 2 ([Projeto_Final_de_Curso_2](https://github.com/anabiaboorges/Projeto_Final_de_Curso_2)).

## Conteúdo

```
ambiente_5g/                      cópia de /home/bianca/ambiente_5g da VM
├── docker-compose.yml            5GC Open5GS 2.7.6 + MongoDB 7.0, UERANSIM (gNB, UE), UPF, DN
├── config_open5gs/               amf.yaml, smf.yaml
├── config_upf/                   upf.yaml + Dockerfile da UPF com ferramentas eBPF
├── config_ueransim/              gnb.yaml, ue.yaml, Dockerfile, geradores URLLC/eMBB
├── pesquisa_galvao/              classificador Random Forest (Galvão et al.) em kernel e em espaço de usuário
├── classificador_{baseline,kernel,user}.sh   rodadas do caso de uso (30 iterações)
├── resultados_kernel/            saídas do classificador in-kernel e do mpstat (30 iterações)
├── setup_cpu_affinity.sh         afinidade de CPU / RPS das interfaces
└── xdp_pass.c, xdp_pass.o        programa XDP_PASS (teste de XDP nativo em veth)

estado_vm_2026-10-17/             estado da VM no momento da cópia
├── docker/                       compose resolvido, imagens (digests), histórico de build, inspect de contêineres e redes
├── conteineres/                  docker diff de cada contêiner
├── mongo/                        assinantes exportados SEM as chaves (K/OPc)
└── sistema/                      inventário da VM (sistema, rede, Docker, eBPF, ferramentas), kernel, crontab
```

## Ambiente

| Item | Valor em 17/10/2026 |
|---|---|
| VM | Ubuntu 22.04.5, kernel 5.15.0-190 (PFC 1 medido no 5.15.0-176), 8 vCPU Xeon Gold 5318Y, 31 GiB, KVM |
| Docker | 29.4.1 |
| Redes | SBI 10.110/16 · N2 10.120/16 · N3 10.130/16 · N4 10.140/16 · N6 10.150/16 |
| CPUs | controle 0–1 · UPF 2–3 · gNB 4–5 · UE e DN 6–7 |
| BCC | 0.36.1 compilado em `/opt/bcc` (montado na UPF); 0.18 do sistema |

## Como recriar

1. Instalar Docker e o BCC 0.36.1 em `/opt/bcc` (a imagem da UPF monta `/opt/bcc`, `/lib/modules`, `/sys/kernel/btf` e `/sys/fs/bpf` do host).
2. `cd ambiente_5g && docker compose up -d --build` (as imagens `b-upf`, `b-ueransim-gnb` e `b-ueransim-ue` são construídas pelos Dockerfiles em `config_upf/` e `config_ueransim/`; o histórico exato está em `estado_vm_2026-10-17/docker/historico_*.txt`).
3. Cadastrar o assinante `imsi-999700000000001` (DNN `internet`, slice 1/010203) no WebUI/MongoDB, usando a K/OPc do `config_ueransim/ue.yaml` (valores de teste padrão do UERANSIM/Open5GS).
4. Opcional: `sudo ./setup_cpu_affinity.sh` antes das rodadas.

## Observações

- As imagens Docker não estão no repositório (tamanho); apenas os Dockerfiles e o histórico de build.
- O IP público e o MAC da VM foram ocultados no inventário.
- Os programas XDP/TC do experimento de custo de CPU (XDP genérico × TC × tcpdump) não estavam na VM no momento da cópia.
