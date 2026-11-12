# Kafka proxy CI — generated. DO NOT EDIT.
# Builds the proxy and runs the Rust e2e suite against real
# Apache Kafka + Redpanda fixtures, all inside the image.
#   docker build -f docker/kafka-proxy-ci.Dockerfile -t kafka-proxy-ci .
#   docker run --rm kafka-proxy-ci
FROM rust:1-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends default-jdk-headless curl ca-certificates procps && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://downloads.apache.org/kafka/4.3.1/kafka_2.13-4.3.1.tgz -o /tmp/kafka.tgz && mkdir -p /opt/kafka && tar -xzf /tmp/kafka.tgz -C /opt/kafka --strip-components=1 && rm /tmp/kafka.tgz
RUN curl -fsSL https://linux.pkg.redpanda.com/setup-redpanda.deb.sh | bash && apt-get update && apt-get install -y --no-install-recommends redpanda && rm -rf /var/lib/apt/lists/*
ENV KAFKA_HOME=/opt/kafka
WORKDIR /src
COPY rust ./rust
COPY crates/kafka-native ./crates/kafka-native
COPY webrtc/rust ./webrtc/rust
COPY proto ./proto
COPY fixtures ./fixtures
COPY scripts/run-e2e.sh ./scripts/run-e2e.sh
CMD ["bash", "scripts/run-e2e.sh"]
