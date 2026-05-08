FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HTSLIB_CONFIGURE_OPTIONS=--enable-plugins

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        tar \
        bzip2 \
        libhts3 \
        python3 \
        python-is-python3 \
        wget \
        autoconf \
        automake \
        make \
        gcc \
        perl \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libncurses-dev && \
    rm -rf /var/lib/apt/lists/*

# Install samtools 1.21 from source
RUN wget https://github.com/samtools/samtools/releases/download/1.21/samtools-1.21.tar.bz2 && \
    tar -xjf samtools-1.21.tar.bz2 && \
    cd samtools-1.21 && \
    autoheader && autoconf && \
    ./configure && make && make install && \
    cd .. && rm -rf samtools-1.21*

RUN wget https://github.com/CSB5/lofreq/raw/master/dist/lofreq_star-2.1.5_linux-x86-64.tgz && \
    mkdir -p /opt/lofreq && \
    tar -xzf lofreq_star-2.1.5_linux-x86-64.tgz -C /opt/lofreq && \
    rm lofreq_star-2.1.5_linux-x86-64.tgz

ENV PATH="/opt/lofreq/lofreq_star-2.1.5_linux-x86-64/bin:${PATH}"

RUN lofreq version

WORKDIR /data