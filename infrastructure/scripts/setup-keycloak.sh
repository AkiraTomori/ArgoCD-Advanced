
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/../base" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-}"
VALUES_FILE="${VALUES_FILE:-${REPO_ROOT}/environments/test/values-shared.yaml}"
INSTALL_OPERATORS="${INSTALL_OPERATORS:-false}"
DOMAIN="${DOMAIN:-yas.test.com}"
KEYCLOAK_HOSTNAME="${KEYCLOAK_HOSTNAME:-identity.${DOMAIN}}"

if [[ -z "${TARGET_NAMESPACE}" ]]; then
    echo "ERROR: TARGET_NAMESPACE is required"
    echo "Usage: TARGET_NAMESPACE=test-<user>-<svc> ${BASH_SOURCE[0]}"
    exit 1
fi

echo "[INFO] Namespace: ${TARGET_NAMESPACE}"
echo "[INFO] Values file: ${VALUES_FILE}"

kubectl create namespace "${TARGET_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ "${INSTALL_OPERATORS}" == "true" ]]; then
    echo "[INFO] Installing Keycloak CRDs and operator in namespace ${TARGET_NAMESPACE}"
    kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
    kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
    kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n "${TARGET_NAMESPACE}"
fi

echo "[INFO] Deploying Keycloak"
helm dependency build "${BASE_DIR}/keycloak/keycloak"
helm upgrade --install keycloak "${BASE_DIR}/keycloak/keycloak" \
    --namespace "${TARGET_NAMESPACE}" \
    -f "${VALUES_FILE}" \
    --set global.domain="${DOMAIN}" \
    --set hostname="${KEYCLOAK_HOSTNAME}"

echo "[INFO] Keycloak deployment submitted. Pod may restart until PostgreSQL is running."
