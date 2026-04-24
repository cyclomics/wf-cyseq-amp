FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HTSLIB_CONFIGURE_OPTIONS=--enable-plugins

RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        python-is-python3 \
        procps \
        ca-certificates \
        # samtools build deps
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
        libncurses-dev \
        # bedtools build deps
        g++ \
        libbz2-dev \
        liblzma-dev \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Install samtools 1.21 from source
RUN wget https://github.com/samtools/samtools/releases/download/1.21/samtools-1.21.tar.bz2 && \
    tar -xjf samtools-1.21.tar.bz2 && \
    cd samtools-1.21 && \
    autoheader && autoconf && \
    ./configure && make && make install && \
    cd .. && rm -rf samtools-1.21*

# Install bedtools 2.31.1 from source
RUN wget https://github.com/arq5x/bedtools2/releases/download/v2.31.1/bedtools-2.31.1.tar.gz && \
    tar -xzf bedtools-2.31.1.tar.gz && \
    cd bedtools2 && \
    make && make install && \
    cd .. && rm -rf bedtools2 bedtools-2.31.1.tar.gz

RUN python3 -m pip install --no-cache-dir --break-system-packages \
    pandas \
    pysam==0.23.3 \
    tqdm==4.67.3 \
    pyyaml==6.0.3 \
    requests==2.33.1

WORKDIR /opt