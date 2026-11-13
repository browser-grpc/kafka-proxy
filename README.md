# Kafka over gRPC — proxy

A Rust proxy that exposes an Apache Kafka or Redpanda cluster as
the generated `grpcdc.kafka.v1.Kafka` gRPC service (see
[KAFKA.md](KAFKA.md)). Generated clients in every language —
from the main [grpc-over-datachannels](https://github.com/browser-grpc/grpc-over-datachannels)
repo, browser and native — reach Kafka through it over stdio,
length-prefixed TCP, or a WebRTC DataChannel.

**Watch:** [Kafka over gRPC: A Rust Kafka Proxy With Generated Clients](https://youtu.be/KJ98a4ApZ4E) — narrated walkthrough with a live demo against Apache Kafka. Background: [Kafka over gRPC](https://c100k.blogspot.com/2026/10/kafka-over-grpc-rust-kafka-proxy-with.html) on the project blog.

This repository is a generated export (version v0.42.0); the
proxy sources live in `rust/examples/kafka_proxy/`.

## Run

```sh
docker run --rm ghcr.io/browser-grpc/kafka-proxy:latest \
  --tcp 0.0.0.0:50201 --broker kafka:9092
```

Or build it here:

```sh
docker build -f docker/kafka-proxy.Dockerfile -t kafka-proxy .
cd rust && cargo build --release --features kafka-tls,webrtc \
  --example kafka_proxy
```

## Tests

The end-to-end suite (produce/consume, consumer groups,
transactions, compression, restart resume) runs against real
Apache Kafka and Redpanda fixtures inside Docker — nothing to
install:

```sh
docker build -f docker/kafka-proxy-ci.Dockerfile -t kafka-proxy-ci .
docker run --rm kafka-proxy-ci
```

GitHub Actions runs the same image on every push.
