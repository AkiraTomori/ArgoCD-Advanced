#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-}"
CONFIG_FILE="${SCRIPT_DIR}/cluster-config.yaml"

if [[ -z "${TARGET_NAMESPACE}" ]]; then
  echo "ERROR: TARGET_NAMESPACE is required"
  echo "Usage: TARGET_NAMESPACE=test-<user>-<svc> ${BASH_SOURCE[0]}"
  exit 1
fi

# Keep Redis setup consistent with DevOps-YAS script, but deploy into developer namespace.
read -r REDIS_PASSWORD < <(yq -r '.redis.password' "${CONFIG_FILE}")

echo "[INFO] Namespace: ${TARGET_NAMESPACE}"

kubectl create namespace "${TARGET_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install redis \
  --set auth.password="${REDIS_PASSWORD}" \
  --set architecture=replication \
  --set replica.replicaCount=1 \
  --set master.persistence.enabled=true \
  --set master.podSecurityContext.fsGroup=1001 \
  --set master.containerSecurityContext.runAsUser=1001 \
  --set volumePermissions.enabled=true \
  --set master.resources.requests.cpu="100m" \
  --set master.resources.requests.memory="256Mi" \
  --set master.resources.limits.cpu="500m" \
  --set master.resources.limits.memory="512Mi" \
  --set replica.resources.requests.cpu="100m" \
  --set replica.resources.requests.memory="256Mi" \
  --set replica.resources.limits.cpu="500m" \
  --set replica.resources.limits.memory="512Mi" \
  oci://registry-1.docker.io/bitnamicharts/redis \
  -n "${TARGET_NAMESPACE}" \
  --create-namespace \
  --wait --timeout 10m
