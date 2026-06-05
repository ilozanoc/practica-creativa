# syntax=docker/dockerfile:1
FROM eclipse-temurin:17-jre-jammy

ARG KAFKA_VERSION=4.2.0
ARG SCALA_BIN=2.13

ENV KAFKA_HOME=/opt/kafka
ENV PATH="${KAFKA_HOME}/bin:${PATH}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates bash; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fSL "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_BIN}-${KAFKA_VERSION}.tgz" \
         -o /tmp/kafka.tgz; \
    mkdir -p "${KAFKA_HOME}"; \
    tar -xzf /tmp/kafka.tgz -C "${KAFKA_HOME}" --strip-components=1; \
    rm -f /tmp/kafka.tgz; \
    mkdir -p /var/lib/kafka/data

COPY entrypoint.sh /usr/local/bin/kafka-entrypoint.sh
RUN chmod +x /usr/local/bin/kafka-entrypoint.sh

EXPOSE 9092
ENTRYPOINT ["/usr/local/bin/kafka-entrypoint.sh"]
