FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        tar \
        libhts3 \
        python3 \
        python-is-python3 && \
    rm -rf /var/lib/apt/lists/*

COPY lofreq_star-2.1.5_linux-x86-64.tgz /tmp/

RUN mkdir -p /opt/lofreq && \
    tar -xzf /tmp/lofreq_star-2.1.5_linux-x86-64.tgz -C /opt/lofreq && \
    rm /tmp/lofreq_star-2.1.5_linux-x86-64.tgz

ENV PATH="/opt/lofreq/lofreq_star-2.1.5_linux-x86-64/bin:${PATH}"

RUN lofreq version

WORKDIR /data