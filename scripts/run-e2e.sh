#!/usr/bin/env bash
# Run the kafka_proxy Rust e2e suite against a real Apache
# Kafka broker, then a real Redpanda broker. Brokers are
# started here and killed on exit. Fails loudly if a broker
# never opens its port (the suite skips itself without
# KAFKA_PROXY_E2E_BROKER, so the port checks matter).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
REDPANDA_BIN="${REDPANDA_BIN:-$(command -v redpanda || echo /opt/redpanda/bin/redpanda)}"
TMP="$(mktemp -d)"
PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
port_open() {
  (exec 3<>"/dev/tcp/${1%:*}/${1##*:}") 2>/dev/null && exec 3>&- 3<&-
}
wait_port() {
  local deadline=$((SECONDS + $2))
  while ! port_open "$1"; do
    if [ $SECONDS -ge $deadline ]; then
      echo "FAIL: $3 did not open $1 within $2s" >&2
      return 1
    fi
    sleep 1
  done
  echo "ok: $3 listening on $1"
}
start_kafka() {
  local props="$TMP/kafka.properties"
  cat > "$props" <<EOF
process.roles=broker,controller
node.id=1
listeners=PLAINTEXT://0.0.0.0:19092,CONTROLLER://0.0.0.0:19094
advertised.listeners=PLAINTEXT://127.0.0.1:19092
controller.listener.names=CONTROLLER
controller.quorum.voters=1@127.0.0.1:19094
log.dirs=$TMP/kafka-logs
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
group.initial.rebalance.delay.ms=0
num.partitions=1
EOF
  local cluster_id
  cluster_id="$("$KAFKA_HOME/bin/kafka-storage.sh" random-uuid)" || return 1
  "$KAFKA_HOME/bin/kafka-storage.sh" format -t "$cluster_id" -c "$props" --ignore-formatted >"$TMP/kafka-format.log" 2>&1 || return 1
  "$KAFKA_HOME/bin/kafka-server-start.sh" "$props" >"$TMP/kafka.log" 2>&1 &
  PIDS+=($!)
  wait_port 127.0.0.1:19092 180 kafka || { tail -20 "$TMP/kafka.log" >&2; return 1; }
}
start_redpanda() {
  local cfg="$TMP/redpanda.yaml" rpk_bin broker_bin
  rpk_bin="$(dirname "$REDPANDA_BIN")/rpk"
  [ -x "$rpk_bin" ] || rpk_bin="$(command -v rpk || true)"
  [ -n "$rpk_bin" ] || { echo "FAIL: rpk not found" >&2; return 1; }
  broker_bin="$REDPANDA_BIN"
  [ -x "$(dirname "$REDPANDA_BIN")/../libexec/redpanda" ] && broker_bin="$(dirname "$REDPANDA_BIN")/../libexec/redpanda"
  mkdir -p "$TMP/rp-data"
  "$rpk_bin" redpanda config bootstrap --config "$cfg" --self 127.0.0.1 >/dev/null || return 1
  "$rpk_bin" redpanda config set --config "$cfg" redpanda.data_directory "$TMP/rp-data" >/dev/null || return 1
  "$rpk_bin" redpanda config set --config "$cfg" redpanda.rpc_server "{address: 127.0.0.1, port: 33145}" >/dev/null || return 1
  "$rpk_bin" redpanda config set --config "$cfg" redpanda.advertised_rpc_api "{address: 127.0.0.1, port: 33145}" >/dev/null || return 1
  "$rpk_bin" redpanda config set --config "$cfg" redpanda.admin "[{address: 127.0.0.1, port: 9644}]" >/dev/null || return 1
  "$rpk_bin" redpanda config set --config "$cfg" redpanda.kafka_api "[{name: internal, address: 127.0.0.1, port: 19095}, {name: external, address: 127.0.0.1, port: 19093}]" >/dev/null || return 1
  "$rpk_bin" redpanda config set --config "$cfg" redpanda.advertised_kafka_api "[{name: internal, address: 127.0.0.1, port: 19095}, {name: external, address: 127.0.0.1, port: 19093}]" >/dev/null || return 1
  "$broker_bin" --redpanda-cfg "$cfg" --smp 1 --memory 512M >"$TMP/redpanda.log" 2>&1 &
  PIDS+=($!)
  wait_port 127.0.0.1:19093 120 redpanda || { tail -20 "$TMP/redpanda.log" >&2; return 1; }
}
FAILED=0
start_kafka || exit 1
echo "== rust e2e (apache kafka)"
(cd "$ROOT/rust" && KAFKA_PROXY_E2E_BROKER=127.0.0.1:19092 cargo test --locked --test kafka_proxy_e2e) || FAILED=1
if [ -x "$REDPANDA_BIN" ] || command -v redpanda >/dev/null 2>&1; then
  start_redpanda || FAILED=1
  if [ "$FAILED" -eq 0 ]; then
    echo "== rust e2e (redpanda)"
    (cd "$ROOT/rust" && KAFKA_PROXY_E2E_BROKER=127.0.0.1:19093 cargo test --locked --test kafka_proxy_e2e) || FAILED=1
  fi
else
  echo "note: redpanda binary not found; kafka leg only"
fi
exit "$FAILED"
