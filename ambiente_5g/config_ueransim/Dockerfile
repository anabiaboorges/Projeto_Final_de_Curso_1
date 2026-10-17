# /ambiente_5g/config_ueransim/Dockerfile

FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y \
    cmake git gcc g++ libsctp-dev lksctp-tools iproute2
RUN git clone https://github.com/aligungr/UERANSIM && \
    cd UERANSIM && make -j$(nproc)

FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    libsctp-dev \
    lksctp-tools \
    iproute2 \
    iperf3 \
    tcpdump \
    iputils-ping \
    python3 \
    && apt-get clean

COPY --from=builder /UERANSIM/build /ueransim/build
COPY --from=builder /UERANSIM/config /ueransim/config
COPY urllc_generator.py /ueransim/build/
COPY embb_generator.py  /ueransim/build/
WORKDIR /ueransim/build
