#!/usr/bin/env bash
set -euo pipefail

# Safe minikube restart helper for local infrastructure.
# - Starts minikube (optional)
# - Waits for node readiness
# - Detects and auto-heals known Kafka/Elasticsearch crash-loop patterns

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
START_CLUSTER="${START_CLUSTER:-true}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180s}"

KAFKA_NS="${KAFKA_NS:-kafka}"
KAFKA_POD="${KAFKA_POD:-kafka-cluster-combined-0}"
KAFKA_HOSTPATH="${KAFKA_HOSTPATH:-/tmp/hostpath-provisioner/kafka/data-0-kafka-cluster-combined-0}"

ES_NS="${ES_NS:-elasticsearch}"
ES_POD="${ES_POD:-elasticsearch-es-node-0}"
ES_HOSTPATH="${ES_HOSTPATH:-/tmp/hostpath-provisioner/elasticsearch/elasticsearch-data-elasticsearch-es-node-0}"

log() {
  printf '[safe-start] %s\n' "$*"
}

pod_exists() {
  local ns="$1"
  local pod="$2"
  kubectl -n "$ns" get pod "$pod" >/dev/null 2>&1
}

wait_pod_ready() {
  local ns="$1"
  local pod="$2"
  kubectl -n "$ns" wait --for=condition=Ready "pod/${pod}" --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1
}

pod_health_summary() {
  local ns="$1"
  local pod="$2"
  kubectl -n "$ns" get pod "$pod" \
    -o jsonpath='{.status.phase} {.status.containerStatuses[0].ready} {.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].state.waiting.reason}' \
    2>/dev/null || true
}

collect_pod_logs() {
  local ns="$1"
  local pod="$2"
  {
    kubectl -n "$ns" logs "$pod" --tail=200 2>/dev/null || true
    kubectl -n "$ns" logs "$pod" --previous --tail=200 2>/dev/null || true
  }
}

clean_hostpath_on_all_nodes() {
  local path_to_clean="$1"
  local set_perms="${2:-false}"
  local ns="kube-system"
  local node

  mapfile -t nodes < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

  for node in "${nodes[@]}"; do
    local pod_name="hp-clean-${node//[^a-zA-Z0-9-]/-}-$(date +%s)"
    pod_name="${pod_name:0:62}"

    log "Cleaning ${path_to_clean} on node ${node}"

    cat <<EOF | kubectl -n "$ns" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
spec:
  nodeName: ${node}
  restartPolicy: Never
  containers:
    - name: cleaner
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          set -eu
          rm -rf "${path_to_clean}"/* "${path_to_clean}"/.[!.]* "${path_to_clean}"/..?* 2>/dev/null || true
          mkdir -p "${path_to_clean}"
          if [ "${set_perms}" = "true" ]; then
            chmod -R 0777 "${path_to_clean}" || true
          fi
      volumeMounts:
        - name: hp
          mountPath: /tmp/hostpath-provisioner
  volumes:
    - name: hp
      hostPath:
        path: /tmp/hostpath-provisioner
        type: Directory
EOF

    kubectl -n "$ns" wait --for=condition=Ready "pod/${pod_name}" --timeout=60s >/dev/null 2>&1 || true
    kubectl -n "$ns" logs "$pod_name" >/dev/null 2>&1 || true
    kubectl -n "$ns" delete pod "$pod_name" --ignore-not-found >/dev/null 2>&1 || true
  done
}

heal_kafka_if_needed() {
  if ! pod_exists "$KAFKA_NS" "$KAFKA_POD"; then
    log "Kafka pod ${KAFKA_NS}/${KAFKA_POD} not found, skipping heal check"
    return 0
  fi

  if wait_pod_ready "$KAFKA_NS" "$KAFKA_POD"; then
    log "Kafka pod is Ready"
    return 0
  fi

  local logs
  logs="$(collect_pod_logs "$KAFKA_NS" "$KAFKA_POD")"

  if printf '%s' "$logs" | grep -q "Invalid cluster.id"; then
    log "Detected Kafka cluster.id mismatch, performing self-heal"
    kubectl -n "$KAFKA_NS" delete pod "$KAFKA_POD" --ignore-not-found >/dev/null 2>&1 || true
    clean_hostpath_on_all_nodes "$KAFKA_HOSTPATH" true

    # Delete PVC to force clean rebind if storage metadata is stale.
    kubectl -n "$KAFKA_NS" delete pvc data-0-kafka-cluster-combined-0 --ignore-not-found >/dev/null 2>&1 || true

    log "Waiting for Kafka pod to recover"
    wait_pod_ready "$KAFKA_NS" "$KAFKA_POD" || true
  else
    log "Kafka pod not ready, but no known cluster.id mismatch signature was found"
  fi
}

heal_es_if_needed() {
  if ! pod_exists "$ES_NS" "$ES_POD"; then
    log "Elasticsearch pod ${ES_NS}/${ES_POD} not found, skipping heal check"
    return 0
  fi

  if wait_pod_ready "$ES_NS" "$ES_POD"; then
    log "Elasticsearch pod is Ready"
    return 0
  fi

  local logs
  logs="$(collect_pod_logs "$ES_NS" "$ES_POD")"

  if printf '%s' "$logs" | grep -Eq "failed to obtain node locks|AccessDeniedException|node.lock"; then
    log "Detected Elasticsearch data-path lock/permission issue, performing self-heal"
    kubectl -n "$ES_NS" delete pod "$ES_POD" --ignore-not-found >/dev/null 2>&1 || true
    clean_hostpath_on_all_nodes "$ES_HOSTPATH" true

    log "Waiting for Elasticsearch pod to recover"
    wait_pod_ready "$ES_NS" "$ES_POD" || true
  else
    log "Elasticsearch pod not ready, but no known node-lock signature was found"
  fi
}

main() {
  if [[ "$START_CLUSTER" == "true" ]]; then
    log "Starting minikube profile ${MINIKUBE_PROFILE}"
    minikube -p "$MINIKUBE_PROFILE" start
  fi

  log "Waiting for all nodes to become Ready"
  kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null

  log "Running Kafka self-heal checks"
  heal_kafka_if_needed

  log "Running Elasticsearch self-heal checks"
  heal_es_if_needed

  log "Final status"
  kubectl get pods -A | grep -E 'kafka-cluster-combined-0|elasticsearch-es-node-0' || true
}

main "$@"
