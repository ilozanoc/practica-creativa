# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Imagen Spark para la practica creativa 2.
# Spark 4.1.1 (Scala 2.13, Hadoop 3) + conectores declarados en build.sbt.
#
# NOTA IMPORTANTE sobre compatibilidad de conectores con Spark 4.x:
#   - Kafka (source/sink):       funciona   (spark-sql-kafka 4.1.1 nativo)
#   - S3A / MinIO (modelos):     funciona   (hadoop-aws 3.4.2)
#   - Iceberg (reentrenamiento): funciona*  (*runtime 4.0; no hay 4.1 aun)
#   - MongoDB format("mongodb"): RIESGO     (conector 10.4.1 es para Spark 3.5;
#                                            Spark 4 requiere 11.x)
#   - Cassandra format(...):     RIESGO     (conector 3.5.1 es para Spark 3.5;
#                                            no hay release oficial para Spark 4)
#   Estos jars se incluyen porque asi los declara build.sbt (provided); si
#   fallan en runtime es una limitacion del stack del enunciado, no de la
#   infraestructura.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:17-jre-jammy

# ---- Versiones (cambia aqui si alguna URL diera 404 o hay conflicto) -----
ARG SPARK_VERSION=4.1.1
ARG MAVEN=https://repo1.maven.org/maven2

# Spark 4.1.x bundlea Hadoop 3.4.2 (verificado en pom.xml del repo de Spark)
ARG HADOOP_AWS_VERSION=3.4.2
# AWS SDK v1 compatible con Hadoop 3.4.x S3A (SimpleAWSCredentialsProvider)
ARG AWS_SDK_VERSION=1.12.367

# Kafka connector: debe coincidir con la version de Spark
ARG KAFKA_SQL_VERSION=4.1.1
# kafka-clients que usa Spark 4.x (era de Spark 4.0); ajusta a 4.x si la
# conexion al broker Kafka 4.2.0 da error de version de protocolo
ARG KAFKA_CLIENTS_VERSION=3.8.0
ARG COMMONS_POOL2_VERSION=2.12.0

# Conectores segun build.sbt (provided, no bundleados en el JAR)
ARG CASSANDRA_CONN_VERSION=3.5.1   # Spark 3.5 solamente; puede fallar en 4.x
ARG MONGO_CONN_VERSION=10.4.1       # Spark 3.5 solamente; puede fallar en 4.x
ARG MONGO_DRIVER_VERSION=5.1.4

# Iceberg: 4.0 runtime (compatible con Spark 4.0/4.1, no existe runtime 4.1)
ARG ICEBERG_VERSION=1.10.1

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}"
ENV HOME=/home/spark
ENV SPARK_USER=spark

# ---- Utilidades + Python ----
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates bash procps python3 tini; \
    rm -rf /var/lib/apt/lists/*

# ---- Apache Spark 4.1.1 (Scala 2.13 unica; NO lleva sufijo -scala2.13) ----
RUN set -eux; \
    curl -fSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" \
         -o /tmp/spark.tgz; \
    mkdir -p "${SPARK_HOME}"; \
    tar -xzf /tmp/spark.tgz -C "${SPARK_HOME}" --strip-components=1; \
    rm -f /tmp/spark.tgz

# ---- Conectores: descarga directa a $SPARK_HOME/jars ----
ARG SCALA_BIN=2.13
RUN set -eux; \
    cd "${SPARK_HOME}/jars"; \
    for url in \
      "${MAVEN}/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" \
      "${MAVEN}/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" \
      "${MAVEN}/org/apache/spark/spark-sql-kafka-0-10_${SCALA_BIN}/${KAFKA_SQL_VERSION}/spark-sql-kafka-0-10_${SCALA_BIN}-${KAFKA_SQL_VERSION}.jar" \
      "${MAVEN}/org/apache/spark/spark-token-provider-kafka-0-10_${SCALA_BIN}/${KAFKA_SQL_VERSION}/spark-token-provider-kafka-0-10_${SCALA_BIN}-${KAFKA_SQL_VERSION}.jar" \
      "${MAVEN}/org/apache/kafka/kafka-clients/${KAFKA_CLIENTS_VERSION}/kafka-clients-${KAFKA_CLIENTS_VERSION}.jar" \
      "${MAVEN}/org/apache/commons/commons-pool2/${COMMONS_POOL2_VERSION}/commons-pool2-${COMMONS_POOL2_VERSION}.jar" \
      "${MAVEN}/com/datastax/spark/spark-cassandra-connector-assembly_${SCALA_BIN}/${CASSANDRA_CONN_VERSION}/spark-cassandra-connector-assembly_${SCALA_BIN}-${CASSANDRA_CONN_VERSION}.jar" \
      "${MAVEN}/org/apache/iceberg/iceberg-spark-runtime-4.0_${SCALA_BIN}/${ICEBERG_VERSION}/iceberg-spark-runtime-4.0_${SCALA_BIN}-${ICEBERG_VERSION}.jar" \
      "${MAVEN}/org/mongodb/spark/mongo-spark-connector_${SCALA_BIN}/${MONGO_CONN_VERSION}/mongo-spark-connector_${SCALA_BIN}-${MONGO_CONN_VERSION}.jar" \
      "${MAVEN}/org/mongodb/mongodb-driver-sync/${MONGO_DRIVER_VERSION}/mongodb-driver-sync-${MONGO_DRIVER_VERSION}.jar" \
      "${MAVEN}/org/mongodb/mongodb-driver-core/${MONGO_DRIVER_VERSION}/mongodb-driver-core-${MONGO_DRIVER_VERSION}.jar" \
      "${MAVEN}/org/mongodb/bson/${MONGO_DRIVER_VERSION}/bson-${MONGO_DRIVER_VERSION}.jar" \
      "${MAVEN}/org/mongodb/bson-record-codec/${MONGO_DRIVER_VERSION}/bson-record-codec-${MONGO_DRIVER_VERSION}.jar" \
    ; do \
      echo ">> $(basename "$url")"; \
      curl -fSL -O "$url"; \
    done

# ---- Configuracion por defecto (catalogo Iceberg + S3A/MinIO) ----
COPY spark-defaults.conf ${SPARK_HOME}/conf/spark-defaults.conf

# ---- JAR de la practica ----
RUN mkdir -p /app/jars
COPY flight_prediction_2.13-0.1.jar /app/jars/flight_prediction_2.13-0.1.jar

# ---- Usuario spark + permisos ----
RUN set -eux; \
    useradd -r -m -d /home/spark -s /bin/bash spark || true; \
    mkdir -p /home/spark/.ivy2 /shared-jars "${SPARK_HOME}/work" "${SPARK_HOME}/logs"; \
    chmod -R 777 /home/spark "${SPARK_HOME}/work" "${SPARK_HOME}/logs"

WORKDIR /opt/spark
CMD ["/opt/spark/bin/spark-class", "org.apache.spark.deploy.master.Master"]
