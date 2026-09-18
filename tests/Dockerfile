FROM debian:12-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sysbench mariadb-client procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /results
