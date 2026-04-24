#!/usr/bin/env bash
set -euo pipefail

# Deploy full infrastructure for per-developer namespace using charts in ArgoCD-Advanced.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_DIR="${REPO_ROOT}/infrastructure/base"
VALUES_FILE="${VALUES_FILE:-${REPO_ROOT}/environments/test/values-shared.yaml}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-}"
INSTALL_OPERATORS="${INSTALL_OPERATORS:-false}"

if [[ -z "${TARGET_NAMESPACE}" ]]; then
  echo "ERROR: TARGET_NAMESPACE is required"
  echo "Usage: TARGET_NAMESPACE=test-<user>-<svc> ${BASH_SOURCE[0]}"
  exit 1
fi

echo "[INFO] Namespace: ${TARGET_NAMESPACE}"
echo "[INFO] Values file: ${VALUES_FILE}"

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

kubectl create namespace "${TARGET_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ "${INSTALL_OPERATORS}" == "true" ]]; then
  echo "[INFO] Installing cluster-level operators and CRDs"

  helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
    --create-namespace --namespace postgres-operator

  helm upgrade --install kafka-operator strimzi/strimzi-kafka-operator \
    --create-namespace --namespace kafka-operator

  helm upgrade --install elastic-operator elastic/eck-operator \
    --create-namespace --namespace elastic-system

  kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
  kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
  kubectl create namespace keycloak-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n keycloak-system

  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.12.0 \
    --set installCRDs=true \
    --set prometheus.enabled=false \
    --set webhook.timeoutSeconds=4 \
    --set admissionWebhooks.certManager.create=true

  helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
    --create-namespace --namespace observability

  helm upgrade --install grafana-operator oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
    --version v5.0.2 \
    --create-namespace --namespace observability
fi

echo "[INFO] Deploying postgresql"
helm dependency build "${BASE_DIR}/postgres/postgresql"
helm upgrade --install postgresql "${BASE_DIR}/postgres/postgresql" \
  -n "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Deploying pgadmin"
helm dependency build "${BASE_DIR}/postgres/pgadmin"
helm upgrade --install pgadmin "${BASE_DIR}/postgres/pgadmin" \
  -n "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Deploying kafka"
helm dependency build "${BASE_DIR}/kafka/kafka-cluster"
helm upgrade --install kafka "${BASE_DIR}/kafka/kafka-cluster" \
  -n "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Deploying zookeeper"
helm dependency build "${BASE_DIR}/zookeeper"
helm upgrade --install zookeeper "${BASE_DIR}/zookeeper" \
  -n "${TARGET_NAMESPACE}" \
  --wait --timeout 10m

echo "[INFO] Deploying akhq"
helm upgrade --install akhq akhq/akhq \
  -n "${TARGET_NAMESPACE}" \
  --values "${BASE_DIR}/kafka/akhq.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Deploying elasticsearch"
helm dependency build "${BASE_DIR}/elasticsearch/elasticsearch-cluster"
helm upgrade --install elasticsearch "${BASE_DIR}/elasticsearch/elasticsearch-cluster" \
  -n "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Deploying keycloak"
helm dependency build "${BASE_DIR}/keycloak/keycloak"
helm upgrade --install keycloak "${BASE_DIR}/keycloak/keycloak" \
  -n "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --set global.domain=yas.test.com \
  --set hostname=identity.yas.test.com \
  --wait --timeout 10m

echo "[INFO] Deploying redis"
helm dependency build "${BASE_DIR}/redis"
helm upgrade --install redis "${BASE_DIR}/redis" \
  -n "${TARGET_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 10m

echo "[INFO] Deploying loki"
helm upgrade --install loki grafana/loki \
  -n "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/loki.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Deploying tempo"
helm upgrade --install tempo grafana/tempo \
  -n "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/tempo.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Deploying opentelemetry collector"
helm dependency build "${BASE_DIR}/observability/opentelemetry"
helm upgrade --install opentelemetry-collector "${BASE_DIR}/observability/opentelemetry" \
  -n "${TARGET_NAMESPACE}" \
  --wait --timeout 10m

echo "[INFO] Deploying promtail"
helm upgrade --install promtail grafana/promtail \
  -n "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/promtail.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Deploying prometheus stack"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n "${TARGET_NAMESPACE}" \
  -f "${BASE_DIR}/observability/prometheus.values.yaml" \
  --wait --timeout 10m

echo "[INFO] Deploying grafana custom resources"
helm dependency build "${BASE_DIR}/observability/grafana"
helm upgrade --install grafana "${BASE_DIR}/observability/grafana" \
  -n "${TARGET_NAMESPACE}" \
  --set hostname="grafana.yas.test.com" \
  --wait --timeout 10m

echo "[INFO] Full infrastructure deployment completed for namespace ${TARGET_NAMESPACE}"
