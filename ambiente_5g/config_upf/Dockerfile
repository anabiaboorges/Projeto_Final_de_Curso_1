# /ambiente5gbianca/config_upf/Dockerfile
FROM gradiant/open5gs:2.7.6

ENV DEBIAN_FRONTEND=noninteractive
USER root

RUN apt-get update && apt-get install -y \
    iproute2 \
    iptables \
    iputils-ping \
    tcpdump \
    clang \
    llvm \
    libbpf-dev \
    libbpfcc-dev \
    bpfcc-tools \
    bpftool \
    gcc-10 \
    python3-bpfcc \
    && ln -s /usr/bin/gcc-10 /usr/local/bin/gcc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /etc/open5gs
