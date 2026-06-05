#!/usr/bin/env bash
set -euo pipefail

KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
ADV_HOST="${KAFKA_ADVERTISED_HOST:-kafka}"
DATA_DIR="${KAFKA_LOG_DIRS:-/var/lib/kafka/data}"
CFG="/tmp/server.properties"

mkdir -p "${DATA_DIR}"

cat > "${CFG}" <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@localhost:9093
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
advertised.listeners=PLAINTEXT://${ADV_HOST}:9092
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
log.dirs=${DATA_DIR}
num.partitions=1
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
group.initial.rebalance.delay.ms=0
auto.create.topics.enable=true
EOF

if [ ! -f "${DATA_DIR}/meta.properties" ]; then
  echo ">> Formateando almacenamiento KRaft en ${DATA_DIR}"
  CID="$("${KAFKA_HOME}/bin/kafka-storage.sh" random-uuid)"
  "${KAFKA_HOME}/bin/kafka-storage.sh" format -t "${CID}" -c "${CFG}" --ignore-formatted
fi

echo ">> Arrancando Kafka (advertised: ${ADV_HOST}:9092)"
exec "${KAFKA_HOME}/bin/kafka-server-start.sh" "${CFG}"
