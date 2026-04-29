#!/bin/bash
# ===================================================================
# Service Mesh Test Plan - YAS Microservices
# Scope: 3 protected services (`media`, `payment`, `order`)
# Allowed callers: `storefront-bff`, `nginx`
# Deny caller: choose any existing service account (default: `cart`).
# The script will create a temporary pod named mesh-deny-<sa> to run deny checks.
# Yêu cầu: Istio đã cài, sidecar đã inject (pods 2/2), mTLS STRICT
# ===================================================================

set -euo pipefail

NAMESPACE="${NAMESPACE:-yas-dev}"
ALLOW_SA_ONE="${ALLOW_SA_ONE:-storefront-bff}"
ALLOW_SA_TWO="${ALLOW_SA_TWO:-nginx}"
DENY_SA="${DENY_SA:-cart}"

MEDIA_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=media -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
PAYMENT_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=payment -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
ORDER_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=order -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

# Try these paths in order when checking service liveness/allow. Fallback to `/`.
TARGET_PATHS=("/actuator/health" "/")

pod_curl_status() {
  local pod="$1"
  local url="$2"
  local status

  status=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || true)
  if [[ -z "$status" ]]; then
    echo "failed"
    echo "--- debug (curl -sv) ---"
    kubectl exec -n "$NAMESPACE" "$pod" -- curl -sv --max-time 5 "$url" 2>&1 | sed -n '1,120p' || true
  else
    echo "$status"
  fi
}

try_best_path_from_pod() {
  local pod="$1"
  local hostbase="$2"
  local path
  local status

  for path in "${TARGET_PATHS[@]}"; do
    status=$(pod_curl_status "$pod" "${hostbase}${path}")
    if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
      echo "$status"
      return 0
    fi
  done
  # return the last status if none 2xx/3xx
  echo "$status"
}

cleanup_temp_pod() {
  local pod_name="$1"
  kubectl delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}

create_curl_pod() {
  local pod_name="$1"
  local service_account="$2"

  cleanup_temp_pod "$pod_name"

  kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
spec:
  serviceAccountName: ${service_account}
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      command: ["sh", "-c", "sleep 3600"]
EOF

  kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/"$pod_name" --timeout=120s >/dev/null
}

cleanup_all() {
  cleanup_temp_pod "mesh-allow-${ALLOW_SA_ONE}"
  cleanup_temp_pod "mesh-allow-${ALLOW_SA_TWO}"
  cleanup_temp_pod "mesh-deny-${DENY_SA}"
  cleanup_temp_pod "media-test-server"
  cleanup_temp_pod "payment-test-server"
  cleanup_temp_pod "order-test-server"
}

create_test_server() {
  local pod_name="$1"
  local label_name="$2"

  cleanup_temp_pod "$pod_name"

  kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  labels:
    app.kubernetes.io/name: ${label_name}
spec:
  restartPolicy: Never
  containers:
    - name: web
      image: nginx:1.25-alpine
      ports:
        - containerPort: 80
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 1
        periodSeconds: 2
EOF

  kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/"$pod_name" --timeout=120s >/dev/null
}

pod_ip() {
  kubectl get pod -n "$NAMESPACE" "$1" -o jsonpath='{.status.podIP}' 2>/dev/null || true
}

deny_check() {
  local service_name="$1"
  local url="$2"
  local status_code

  status_code=$(kubectl exec -n "$NAMESPACE" mesh-debug -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || true)
  echo "${service_name} HTTP Status: ${status_code:-failed}"

  if [[ "$status_code" == "200" ]]; then
    echo "Unexpected success for deny test against ${service_name}" >&2
    exit 1
  fi
}

echo "=============================================="
echo "  SERVICE MESH TEST PLAN - YAS PROJECT"
echo "  Namespace: $NAMESPACE"
echo "  Date: $(date)"
echo "=============================================="

trap cleanup_all EXIT

# -----------------------------------------------
# TEST 1: Verify mTLS đang hoạt động
# -----------------------------------------------
echo ""
echo ">>> TEST 1: Verify mTLS"
echo "--- 1a. PeerAuthentication status ---"
kubectl get peerauthentication -n "$NAMESPACE"
echo ""

echo "--- 1b. Kiểm tra pods được chọn có sidecar (2/2) ---"
kubectl get pods -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name" | grep -E 'media|payment|order|storefront-bff|nginx' || true
echo ""

echo "--- 1c. Kiểm tra Envoy TLS stats ---"
if [[ -n "$MEDIA_POD" ]]; then
  echo "Pod: $MEDIA_POD"
  kubectl exec -n "$NAMESPACE" "$MEDIA_POD" -c istio-proxy -- pilot-agent request GET stats 2>/dev/null | grep "ssl" | head -10 || true
else
  echo "No media pod found"
fi
echo ""

# -----------------------------------------------
# TEST 2: Authorization Policy - ALLOW / DENY
# -----------------------------------------------
echo ">>> TEST 2: Authorization Policy"
echo ""

echo "--- 2a. tạo pod allow cho storefront-bff ---"
create_curl_pod "mesh-allow-${ALLOW_SA_ONE}" "$ALLOW_SA_ONE"
echo "Pod created: mesh-allow-${ALLOW_SA_ONE}"
echo ""

echo "--- 2b. tạo pod allow cho nginx ---"
create_curl_pod "mesh-allow-${ALLOW_SA_TWO}" "$ALLOW_SA_TWO"
echo "Pod created: mesh-allow-${ALLOW_SA_TWO}"
echo ""

# Map service -> sensible GET path to expect 200 when allowed
declare -A PATH_MAP
# Use concrete GET endpoints likely to return 200 (or empty 200) without auth
PATH_MAP[media]="/medias?ids=1"
PATH_MAP[payment]="/storefront/payment-providers"
PATH_MAP[order]="/storefront/orders/my-orders?productName="

echo "Using service paths: media=${PATH_MAP[media]}, payment=${PATH_MAP[payment]}, order=${PATH_MAP[order]}"
echo ""

echo "--- 2c. allow: storefront-bff -> media/payment/order ---"
echo "Pod: mesh-allow-${ALLOW_SA_ONE}"
echo -n "media HTTP Status: "
try_best_path_from_pod "mesh-allow-${ALLOW_SA_ONE}" "http://media.${NAMESPACE}.svc.cluster.local${PATH_MAP[media]}"
echo -n "payment HTTP Status: "
try_best_path_from_pod "mesh-allow-${ALLOW_SA_ONE}" "http://payment.${NAMESPACE}.svc.cluster.local${PATH_MAP[payment]}"
echo -n "order HTTP Status: "
try_best_path_from_pod "mesh-allow-${ALLOW_SA_ONE}" "http://order.${NAMESPACE}.svc.cluster.local${PATH_MAP[order]}"
echo ""

echo "--- 2d. allow: nginx -> media/payment/order ---"
echo "Pod: mesh-allow-${ALLOW_SA_TWO}"
echo -n "media HTTP Status: "
try_best_path_from_pod "mesh-allow-${ALLOW_SA_TWO}" "http://media.${NAMESPACE}.svc.cluster.local${PATH_MAP[media]}"
echo -n "payment HTTP Status: "
try_best_path_from_pod "mesh-allow-${ALLOW_SA_TWO}" "http://payment.${NAMESPACE}.svc.cluster.local${PATH_MAP[payment]}"
echo -n "order HTTP Status: "
try_best_path_from_pod "mesh-allow-${ALLOW_SA_TWO}" "http://order.${NAMESPACE}.svc.cluster.local${PATH_MAP[order]}"
echo ""

echo "--- 2e. deny: ${DENY_SA} -> media/payment/order (expected: DENY) ---"
kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: mesh-deny-${DENY_SA}
spec:
  serviceAccountName: ${DENY_SA}
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      command: ["sh", "-c", "sleep 3600"]
EOF

kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/mesh-deny-${DENY_SA} --timeout=120s >/dev/null
echo "Pod: mesh-deny-${DENY_SA} (sa: ${DENY_SA})"
deny_check "media" "http://media.${NAMESPACE}.svc.cluster.local/"
deny_check "payment" "http://payment.${NAMESPACE}.svc.cluster.local/"
deny_check "order" "http://order.${NAMESPACE}.svc.cluster.local/"
echo ""

# -----------------------------------------------
# TEST 3: Retry Policy
# -----------------------------------------------
echo ">>> TEST 3: Retry Policy (VirtualService)"
echo "--- 3a. VirtualService cấu hình ---"
kubectl get virtualservice -n "$NAMESPACE" | grep -E 'media-retry|payment-retry|order-retry' || true
echo ""

echo "--- 3b. Kiểm tra retry config trong Envoy ---"
if [[ -n "$MEDIA_POD" ]]; then
  kubectl exec -n "$NAMESPACE" "$MEDIA_POD" -c istio-proxy -- pilot-agent request GET config_dump 2>/dev/null | grep -A5 "retry_policy" | head -20 || true
fi
echo ""

echo "--- 3c. Envoy access logs (xem retry attempts) ---"
if [[ -n "$ORDER_POD" ]]; then
  kubectl logs "$ORDER_POD" -n "$NAMESPACE" -c istio-proxy --tail=10 2>/dev/null || true
fi
echo ""

echo "=============================================="
echo "  TEST COMPLETED"
echo "=============================================="