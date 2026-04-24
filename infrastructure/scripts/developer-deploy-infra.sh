#!/usr/bin/env bash
set -euo pipefail

# Deploy full infrastructure for per-developer namespace using charts in ArgoCD-Advanced.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALUES_FILE="${VALUES_FILE:-${REPO_ROOT}/environments/test/values-shared.yaml}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-}"
INSTALL_OPERATORS="${INSTALL_OPERATORS:-false}"
DOMAIN="${DOMAIN:-yas.test.com}"

if [[ -z "${TARGET_NAMESPACE}" ]]; then
  echo "ERROR: TARGET_NAMESPACE is required"
  echo "Usage: TARGET_NAMESPACE=test-<user>-<svc> ${BASH_SOURCE[0]}"
  exit 1
fi

echo "[INFO] Namespace: ${TARGET_NAMESPACE}"
echo "[INFO] Values file: ${VALUES_FILE}"

echo "[INFO] Phase 1/3: setup-keycloak"
TARGET_NAMESPACE="${TARGET_NAMESPACE}" \
VALUES_FILE="${VALUES_FILE}" \
INSTALL_OPERATORS="${INSTALL_OPERATORS}" \
DOMAIN="${DOMAIN}" \
bash "${SCRIPT_DIR}/setup-keycloak.sh"

echo "[INFO] Phase 2/3: setup-redis"
TARGET_NAMESPACE="${TARGET_NAMESPACE}" \
VALUES_FILE="${VALUES_FILE}" \
bash "${SCRIPT_DIR}/setup-redis.sh"

echo "[INFO] Phase 3/3: setup-cluster"
TARGET_NAMESPACE="${TARGET_NAMESPACE}" \
VALUES_FILE="${VALUES_FILE}" \
INSTALL_OPERATORS="${INSTALL_OPERATORS}" \
DOMAIN="${DOMAIN}" \
bash "${SCRIPT_DIR}/setup-cluster.sh"

echo "[INFO] Full infrastructure deployment completed for namespace ${TARGET_NAMESPACE}"
