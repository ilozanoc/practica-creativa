# Práctica Creativa 2 — Big Data con Spark, Kafka, Cassandra, MinIO e Iceberg

Sistema de predicción de retrasos de vuelos desplegable en **Docker Compose** (opción 1) o **Kubernetes GKE** (opción 2), con entrenamiento en deploy-mode cluster de Spark, seguimiento con MLflow y orquestación con Airflow.

---

## Requisitos previos

### Software
- Docker Engine ≥ 24 instalado en la VM
- `gcloud` CLI autenticado
- `kubectl` + `gke-gcloud-auth-plugin`
- Python 3.x (para scripts auxiliares)

### VM recomendada
- **SO**: Debian 12 (Bookworm) — *no Ubuntu*
- **Tipo**: `e2-standard-4` o superior (mínimo `e2-standard-2 × 2 nodos` en GKE)

### Datos de vuelo (obligatorio tras clonar)
> Los datos de vuelo **ya están en el repositorio** — no hace falta descargar nada antes de arrancar.
```bash
bash resources/download_data.sh
```
Esto descarga en `data/`:
- `simple_flight_delay_features.jsonl.bz2` (~4.5 MB)
- `origin_dest_distances.jsonl` (~218 KB)

---

## Instalación de Docker en Debian

> ⚠️ La VM es Debian, **no Ubuntu**. El repo de Docker para Ubuntu da error 404 en Debian.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

---

## Lanzamiento

```bash
git clone "https://github.com/ilozanoc/practica-creativa"
cd practica-creativa
bash resources/download_data.sh   # OBLIGATORIO
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
bash practica.sh
```

Selecciona **opción 1** (Docker Compose) u **opción 2** (Kubernetes GKE).

---

## Opción 1 — Docker Compose

### Tiempo de arranque
El primer arranque tarda **~15 minutos** mientras se construyen y levantan todos los contenedores.

### Firewall GCP — puertos Docker
La regla existente `practica-creativa` solo abre los puertos originales. Añadir los puertos de Grafana, MLflow, Airflow y Prometheus:

```bash
gcloud compute firewall-rules update practica-creativa \
  --allow tcp:9042,tcp:9092,tcp:2181,tcp:7077,tcp:8080,tcp:5001,tcp:4040,tcp:9870,tcp:9000,tcp:9001,tcp:3000,tcp:5002,tcp:8081,tcp:9090 \
  --project YOUR_PROJECT_ID
```

> ⚠️ No crear una regla nueva con `--target-tags` a menos que la VM tenga ese tag asignado. Si la VM no tiene el tag, la regla no aplica.

### URLs de acceso (IP_VM = IP externa de la VM)

| Servicio | URL | Credenciales |
|---|---|---|
| Flask UI + Predicciones | `http://IP_VM:5001` | — |
| Spark UI | `http://IP_VM:8080` | — |
| MLflow | `http://IP_VM:5002` | — |
| Airflow | `http://IP_VM:8081` | admin / admin |
| MinIO | `http://IP_VM:9001` | minioadmin / minioadmin |
| Grafana | `http://IP_VM:3000` | admin / admin |
| Prometheus | `http://IP_VM:9090` | — |

### Airflow en Docker
Si Airflow no arranca tras el primer `docker-compose up`:
```bash
docker restart airflow
```

---

## Opción 2 — Kubernetes GKE

### Variables de entorno necesarias
```bash
export PROJECT_ID="tu-project-id"
export GKE_ZONE="europe-southwest1-a"
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
```

### Crear cluster GKE
El script crea el cluster automáticamente. Si hay error de cuota con `e2-standard-4 × 3 nodos`:
```bash
gcloud container clusters create practica-k8s \
  --zone="$GKE_ZONE" \
  --num-nodes=2 \
  --machine-type=e2-standard-2 \
  --disk-type=pd-balanced \
  --disk-size=100 \
  --enable-ip-alias
```

### Project ID en los YAMLs
Si los YAMLs tienen el project ID del autor hardcodeado:
```bash
> Los YAMLs de K8s se actualizan automáticamente al ejecutar `practica.sh`.
```

### Firewall GCP — NodePorts K8s
```bash
# Obtener tag de red de los nodos GKE
gcloud compute instances describe \
  $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') \
  --zone $GKE_ZONE --format='value(tags.items)'

# Crear regla con ese tag
gcloud compute firewall-rules create allow-k8s-nodeports \
  --allow tcp:30001,tcp:30880,tcp:30300,tcp:30502,tcp:30901,tcp:30808,tcp:30909 \
  --target-tags TAG_OBTENIDO \
  --project YOUR_PROJECT_ID
```

### URLs de acceso K8s (NODE_IP = IP externa de cualquier nodo)

| Servicio | NodePort | URL |
|---|---|---|
| Flask UI + Predicciones | 30001 | `http://NODE_IP:30001` |
| Spark UI (deploy-mode cluster) | 30880 | `http://NODE_IP:30880` |
| MLflow | 30502 | `http://NODE_IP:30502` |
| Airflow | 30808 | `http://NODE_IP:30808` |
| MinIO | 30901 | `http://NODE_IP:30901` |
| Grafana | 30300 | `http://NODE_IP:30300` |
| Prometheus | 30909 | `http://NODE_IP:30909` |

---

## Deploy-mode cluster en Spark

El predictor y el entrenamiento se ejecutan en **deploy-mode cluster**: el driver corre en un worker, no en el cliente. Verificación en Spark UI (`NODE_IP:30880`):

- **Running Drivers**: muestra `es.upm.dit.ging.predictor.MakePrediction` con worker asignado
- **Running Applications**: vacío — normal en cluster mode

---

## Reentrenamiento del modelo (opción 4 del menú)

El DAG `retrain_flight_delay_model` de Airflow:
1. Para el predictor
2. Crea/actualiza la tabla Iceberg en MinIO
3. Lanza `TrainModel` en deploy-mode cluster (~7 minutos)
4. Registra el run en MLflow (`flight_delay_prediction`)
5. Reinicia el predictor con los nuevos modelos

---

## Errores frecuentes y soluciones

### Docker: `Repository does not have a Release file`
**Causa**: repo de Ubuntu usado en Debian.
**Fix**: ver sección instalación Docker en Debian.

### K8s: `ImagePullBackOff` con project ID incorrecto
```bash
> Los YAMLs de K8s se actualizan automáticamente al ejecutar `practica.sh`.
kubectl rollout restart deployment --all
```

### K8s: Predicción se queda en "Processing..."
**Causa A**: Cassandra sin distancias → ejecutar opción 2 del menú.
**Causa B**: Sin modelos entrenados → ejecutar opción 4 del menú.

### K8s: Airflow scheduler crashea con `LocalExecutor + SQLite`
```bash
kubectl set env deployment/airflow AIRFLOW__CORE__EXECUTOR=SequentialExecutor
```

### K8s: Airflow DAG no aparece (`RuntimeError: Detected recursive loop`)
**Causa**: symlink loop del ConfigMap mount en `/opt/airflow/dags/`.
**Fix**: ya corregido en el YAML — usa `/opt/airflow/dags-cm/` con `AIRFLOW__CORE__DAGS_FOLDER`.

### K8s: Airflow scheduler no arranca
**Causa**: el comando solo lanza el webserver.
**Fix**: el YAML debe lanzar ambos procesos:
```bash
kubectl patch deployment airflow --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["bash","-c","airflow db migrate && airflow users create --username admin --password admin --firstname Admin --lastname Admin --role Admin --email admin@example.com 2>/dev/null || true && airflow webserver --port 8080 & exec airflow scheduler"]}]'
```

### Firewall: algunos servicios no cargan
**Causa**: regla con `--target-tags` que no coincide con el tag de la VM.
**Fix**: actualizar la regla `practica-creativa` existente (sin target-tags) en vez de crear una nueva.

---

## Apagar el cluster GKE

```bash
gcloud container clusters resize practica-k8s --num-nodes=0 \
  --zone europe-southwest1-a --quiet
```

Volver a levantar:
```bash
gcloud container clusters resize practica-k8s --num-nodes=2 \
  --zone europe-southwest1-a --quiet
gcloud container clusters get-credentials practica-k8s \
  --zone europe-southwest1-a --project YOUR_PROJECT_ID
```
