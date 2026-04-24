#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_DIR="${REPO_ROOT}/infrastructure/base"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-}"
VALUES_FILE="${VALUES_FILE:-${REPO_ROOT}/environments/test/values-shared.yaml}"
INSTALL_OPERATORS="${INSTALL_OPERATORS:-false}"
DOMAIN="${DOMAIN:-yas.test.com}"
POSTGRES_OPERATOR_NAMESPACE_DEFAULT="${POSTGRES_OPERATOR_NAMESPACE_DEFAULT:-postgres}"
KAFKA_OPERATOR_NAMESPACE_DEFAULT="${KAFKA_OPERATOR_NAMESPACE_DEFAULT:-kafka}"
ELASTIC_OPERATOR_NAMESPACE_DEFAULT="${ELASTIC_OPERATOR_NAMESPACE_DEFAULT:-elasticsearch}"
CERT_MANAGER_NAMESPACE_DEFAULT="${CERT_MANAGER_NAMESPACE_DEFAULT:-cert-manager}"
OTEL_OPERATOR_NAMESPACE_DEFAULT="${OTEL_OPERATOR_NAMESPACE_DEFAULT:-observability}"
GRAFANA_OPERATOR_NAMESPACE_DEFAULT="${GRAFANA_OPERATOR_NAMESPACE_DEFAULT:-observability}"

if [[ -z "${TARGET_NAMESPACE}" ]]; then
  echo "ERROR: TARGET_NAMESPACE is required"
  echo "Usage: TARGET_NAMESPACE=test-<user>-<svc> ${BASH_SOURCE[0]}"
  exit 1
fi

echo "[INFO] Namespace: ${TARGET_NAMESPACE}"
echo "[INFO] Values file: ${VALUES_FILE}"

kubectl create namespace "${TARGET_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Add chart repos and update.
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator >/dev/null 2>&1 || true
helm repo add strimzi https://strimzi.io/charts/ >/dev/null 2>&1 || true
helm repo add akhq https://akhq.io/ >/dev/null 2>&1 || true
helm repo add elastic https://helm.elastic.co >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null

resolve_release_namespace() {
  local release_name="$1"
  local default_namespace="$2"
  local existing_namespace

  existing_namespace="$(helm list -A --filter "^${release_name}$" 2>/dev/null | awk 'NR==2 {print $2}')"
  if [[ -n "${existing_namespace}" ]]; then
    echo "${existing_namespace}"
  else
    echo "${default_namespace}"
  fi
}

if [[ "${INSTALL_OPERATORS}" == "true" ]]; then
  echo "[INFO] Installing cluster-level operators and CRDs"

  POSTGRES_OPERATOR_NAMESPACE="$(resolve_release_namespace "postgres-operator" "${POSTGRES_OPERATOR_NAMESPACE_DEFAULT}")"
  KAFKA_OPERATOR_NAMESPACE="$(resolve_release_namespace "kafka-operator" "${KAFKA_OPERATOR_NAMESPACE_DEFAULT}")"
  ELASTIC_OPERATOR_NAMESPACE="$(resolve_release_namespace "elastic-operator" "${ELASTIC_OPERATOR_NAMESPACE_DEFAULT}")"
  CERT_MANAGER_NAMESPACE="$(resolve_release_namespace "cert-manager" "${CERT_MANAGER_NAMESPACE_DEFAULT}")"
  OTEL_OPERATOR_NAMESPACE="$(resolve_release_namespace "opentelemetry-operator" "${OTEL_OPERATOR_NAMESPACE_DEFAULT}")"
  GRAFANA_OPERATOR_NAMESPACE="$(resolve_release_namespace "grafana-operator" "${GRAFANA_OPERATOR_NAMESPACE_DEFAULT}")"

  echo "[INFO] Operator namespace (postgres-operator): ${POSTGRES_OPERATOR_NAMESPACE}"
  echo "[INFO] Operator namespace (kafka-operator): ${KAFKA_OPERATOR_NAMESPACE}"
  echo "[INFO] Operator namespace (elastic-operator): ${ELASTIC_OPERATOR_NAMESPACE}"
  echo "[INFO] Operator namespace (cert-manager): ${CERT_MANAGER_NAMESPACE}"
  echo "[INFO] Operator namespace (opentelemetry-operator): ${OTEL_OPERATOR_NAMESPACE}"
  echo "[INFO] Operator namespace (grafana-operator): ${GRAFANA_OPERATOR_NAMESPACE}"

  kubectl create namespace "${POSTGRES_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${KAFKA_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${ELASTIC_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${CERT_MANAGER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${OTEL_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${GRAFANA_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
    --create-namespace --namespace "${POSTGRES_OPERATOR_NAMESPACE}"

  helm upgrade --install kafka-operator strimzi/strimzi-kafka-operator \
    --create-namespace --namespace "${KAFKA_OPERATOR_NAMESPACE}"

  helm upgrade --install elastic-operator elastic/eck-operator \
    --create-namespace --namespace "${ELASTIC_OPERATOR_NAMESPACE}"

  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace "${CERT_MANAGER_NAMESPACE}" \
    --create-namespace \
    --version v1.12.0 \
    --set installCRDs=true \
    --set prometheus.enabled=false \
    --set webhook.timeoutSeconds=4 \
    --set admissionWebhooks.certManager.create=true

  helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
    --create-namespace --namespace "${OTEL_OPERATOR_NAMESPACE}"

  helm upgrade --install grafana-operator oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
    --version v5.0.2 \
    --create-namespace --namespace "${GRAFANA_OPERATOR_NAMESPACE}"
fi

echo "[INFO] Installing PostgreSQL"
helm dependency build "${BASE_DIR}/postgres/postgresql"
helm upgrade --install postgres "${BASE_DIR}/postgres/postgresql" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Installing pgadmin"
helm dependency build "${BASE_DIR}/postgres/pgadmin"
helm upgrade --install pgadmin "${BASE_DIR}/postgres/pgadmin" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Installing Kafka cluster"
helm dependency build "${BASE_DIR}/kafka/kafka-cluster"
helm upgrade --install kafka-cluster "${BASE_DIR}/kafka/kafka-cluster" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Installing Zookeeper"
helm dependency build "${BASE_DIR}/zookeeper"
helm upgrade --install zookeeper "${BASE_DIR}/zookeeper" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  --wait --timeout 10m

echo "[INFO] Installing AKHQ"
helm upgrade --install akhq akhq/akhq \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  --values "${BASE_DIR}/kafka/akhq.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Installing Elasticsearch"
helm dependency build "${BASE_DIR}/elasticsearch/elasticsearch-cluster"
helm upgrade --install elasticsearch-cluster "${BASE_DIR}/elasticsearch/elasticsearch-cluster" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Installing Loki"
helm upgrade --install loki grafana/loki \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/loki.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Installing Tempo"
helm upgrade --install tempo grafana/tempo \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/tempo.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Installing OpenTelemetry operator and collector"
helm dependency build "${BASE_DIR}/observability/opentelemetry"
helm upgrade --install opentelemetry-collector "${BASE_DIR}/observability/opentelemetry" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  --wait --timeout 10m

echo "[INFO] Installing Promtail"
helm upgrade --install promtail grafana/promtail \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  --values "${BASE_DIR}/observability/promtail.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Installing Prometheus stack"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/prometheus.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Installing Grafana operator and resources"
helm dependency build "${BASE_DIR}/observability/grafana"
helm upgrade --install grafana "${BASE_DIR}/observability/grafana" \
  --create-namespace --namespace "${TARGET_NAMESPACE}" \
  --set hostname="grafana.${DOMAIN}" \
  --wait --timeout 10m
