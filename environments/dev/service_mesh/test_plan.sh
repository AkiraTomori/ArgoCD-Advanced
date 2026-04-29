#!/bin/bash
# ===================================================================
# Service Mesh Test Plan - YAS Microservices
# Yêu cầu: Istio đã cài, sidecar đã inject (pods 2/2), mTLS STRICT
# Mục tiêu: kiểm tra ALLOW vs DENY (403) và retry evidence (500)
# Ghi chú: script này IGNORE 404 (treated as 'reached but no handler')
# ===================================================================

set -e
NAMESPACE="${NAMESPACE:-yas-dev}"

get_pod() {
  local label_selector="$1"
  local pod_name

  pod_name=$(kubectl get pod -n "$NAMESPACE" -l "$label_selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  echo "$pod_name"
}

get_backend_pod() {
  local app_name="$1"
  local pod_name

  pod_name=$(get_pod "app.kubernetes.io/name=${app_name}")
  if [[ -z "$pod_name" ]]; then
    pod_name=$(get_pod "app=${app_name}")
  fi
  echo "$pod_name"
}

create_curl_pod() {
  local pod_name="$1"
  local service_account="$2"

  kubectl delete pod -n "$NAMESPACE" "$pod_name" --ignore-not-found >/dev/null 2>&1 || true
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

cleanup_curl_pod() {
  local pod_name="$1"

  kubectl delete pod -n "$NAMESPACE" "$pod_name" --ignore-not-found >/dev/null 2>&1 || true
}

create_retry_probe() {
  kubectl delete pod -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete svc -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete virtualservice -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete destinationrule -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true

  kubectl apply -n "$NAMESPACE" -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: mesh-retry-probe
  labels:
    app: mesh-retry-probe
  annotations:
    sidecar.istio.io/inject: "true"
spec:
  restartPolicy: Never
  containers:
    - name: probe
      image: python:3.11-alpine
      ports:
        - containerPort: 8080
      command:
        - python
        - -u
        - -c
        - |
          from http.server import BaseHTTPRequestHandler, HTTPServer

          class Handler(BaseHTTPRequestHandler):
              def do_GET(self):
                  print(f"REQUEST {self.path}", flush=True)
                  self.send_response(500)
                  self.send_header("Content-Type", "text/plain")
                  self.end_headers()
                  self.wfile.write(b"upstream failure")

              def log_message(self, format, *args):
                  return

          HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
---
apiVersion: v1
kind: Service
metadata:
  name: mesh-retry-probe
spec:
  selector:
    app: mesh-retry-probe
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: mesh-retry-probe
spec:
  host: mesh-retry-probe.yas-dev.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: mesh-retry-probe
spec:
  hosts:
    - mesh-retry-probe.yas-dev.svc.cluster.local
  http:
    - route:
        - destination:
            host: mesh-retry-probe.yas-dev.svc.cluster.local
            port:
              number: 80
      retries:
        attempts: 3
        perTryTimeout: 2s
        retryOn: gateway-error,connect-failure,refused-stream,5xx
      timeout: 8s
EOF

  kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/mesh-retry-probe --timeout=120s >/dev/null
}

cleanup_retry_probe() {
  kubectl delete virtualservice -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete destinationrule -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete svc -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete pod -n "$NAMESPACE" mesh-retry-probe --ignore-not-found >/dev/null 2>&1 || true
}

http_status_from_pod() {
  local pod_name="$1"
  local url="$2"

  kubectl exec -n "$NAMESPACE" "$pod_name" -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || true
}

echo "=============================================="
echo "  SERVICE MESH TEST PLAN - YAS PROJECT"
echo "  Namespace: $NAMESPACE"
echo "  Date: $(date)"
echo "=============================================="

# -----------------------------------------------
# TEST 1: Verify mTLS đang hoạt động
# -----------------------------------------------
echo ""
echo ">>> TEST 1: Verify mTLS"
echo "--- 1a. PeerAuthentication status ---"
kubectl get peerauthentication -n $NAMESPACE
echo ""

echo "--- 1b. Kiểm tra tất cả pods đều có sidecar (2/2) ---"
kubectl get pods -n $NAMESPACE -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name" | head -40
echo ""

echo "--- 1c. Kiểm tra Envoy TLS stats ---"
PRODUCT_POD=$(get_backend_pod product)
if [[ -n "$PRODUCT_POD" ]]; then
  echo "Pod: $PRODUCT_POD"
  kubectl exec -n $NAMESPACE $PRODUCT_POD -c istio-proxy -- pilot-agent request GET stats 2>/dev/null | grep "ssl" | head -10 || true
else
  echo "No product pod found"
fi
echo ""

# -----------------------------------------------
# TEST 2: Authorization Policy - ALLOW/DENY (focus on 403)
# Note: 404 are ignored (reported but not considered failure)
# -----------------------------------------------
echo ">>> TEST 2: Authorization Policy"

ORDER_POD=$(get_backend_pod order)
PRODUCT_POD=$(get_backend_pod product)
NGINX_POD=$(get_pod "app=nginx")
MEDIA_POD=$(get_backend_pod media)
PAYMENT_POD=$(get_backend_pod payment)
TAX_POD=$(get_backend_pod tax)

if [[ -z "$ORDER_POD" || -z "$PRODUCT_POD" || -z "$NGINX_POD" || -z "$MEDIA_POD" || -z "$PAYMENT_POD" || -z "$TAX_POD" ]]; then
  echo "One or more required pods were not found."
  echo "order=$ORDER_POD product=$PRODUCT_POD nginx=$NGINX_POD media=$MEDIA_POD payment=$PAYMENT_POD tax=$TAX_POD"
  exit 1
fi

trap 'cleanup_curl_pod mesh-test-order; cleanup_curl_pod mesh-test-product; cleanup_curl_pod mesh-test-nginx; cleanup_curl_pod mesh-test-tax; cleanup_retry_probe' EXIT

create_curl_pod mesh-test-order order
create_curl_pod mesh-test-product product
create_curl_pod mesh-test-nginx nginx
create_curl_pod mesh-test-tax tax

echo ""
echo "--- 2a. nginx -> media (SHOULD BE ALLOWED) ---"
echo "Pod: mesh-test-nginx (sa: nginx) -> media:80"
STATUS=$(http_status_from_pod mesh-test-nginx http://media:80/)
echo "HTTP Status: ${STATUS:-failed}"
if [[ "$STATUS" == "403" ]]; then
  echo "RESULT: DENIED (403)"
elif [[ "$STATUS" == "500" ]]; then
  echo "RESULT: SERVER ERROR (500)"
else
  echo "RESULT: reached (status ${STATUS:-unknown}) - OK for policy check (404 ignored)"
fi
echo ""

echo "--- 2b. nginx -> payment (SHOULD BE ALLOWED) ---"
echo "Pod: mesh-test-nginx (sa: nginx) -> payment:80"
STATUS=$(http_status_from_pod mesh-test-nginx http://payment:80/)
echo "HTTP Status: ${STATUS:-failed}"
if [[ "$STATUS" == "403" ]]; then
  echo "RESULT: DENIED (403)"
elif [[ "$STATUS" == "500" ]]; then
  echo "RESULT: SERVER ERROR (500)"
else
  echo "RESULT: reached (status ${STATUS:-unknown}) - OK for policy check (404 ignored)"
fi
echo ""

echo "--- 2c. tax -> media (SHOULD BE DENIED - 403) ---"
echo "Pod: mesh-test-tax (sa: tax) -> media:80"
STATUS=$(http_status_from_pod mesh-test-tax http://media:80/)
echo "HTTP Status: ${STATUS:-failed}"
if [[ "$STATUS" == "403" ]]; then
  echo "RESULT: DENIED (403) - expected"
elif [[ "$STATUS" == "500" ]]; then
  echo "RESULT: SERVER ERROR (500)"
else
  echo "RESULT: reached (status ${STATUS:-unknown}) - NOTE: 404 is ignored"
fi
echo ""

echo "--- 2d. product -> payment (SHOULD BE DENIED - 403) ---"
echo "Pod: mesh-test-product (sa: product) -> payment:80"
STATUS=$(http_status_from_pod mesh-test-product http://payment:80/)
echo "HTTP Status: ${STATUS:-failed}"
if [[ "$STATUS" == "403" ]]; then
  echo "RESULT: DENIED (403) - expected"
elif [[ "$STATUS" == "500" ]]; then
  echo "RESULT: SERVER ERROR (500)"
else
  echo "RESULT: reached (status ${STATUS:-unknown}) - NOTE: 404 is ignored"
fi
echo ""

echo "--- 2e. order -> payment (SHOULD BE DENIED - 403) ---"
echo "Pod: mesh-test-order (sa: order) -> payment:80"
STATUS=$(http_status_from_pod mesh-test-order http://payment:80/)
echo "HTTP Status: ${STATUS:-failed}"
if [[ "$STATUS" == "403" ]]; then
  echo "RESULT: DENIED (403) - expected"
elif [[ "$STATUS" == "500" ]]; then
  echo "RESULT: SERVER ERROR (500)"
else
  echo "RESULT: reached (status ${STATUS:-unknown}) - NOTE: 404 is ignored"
fi
echo ""

# -----------------------------------------------
# TEST 3: Retry Policy
# -----------------------------------------------
echo ">>> TEST 3: Retry Policy (VirtualService)"
echo "--- 3a. VirtualService cấu hình ---"
kubectl get virtualservice -n $NAMESPACE || true
echo ""

echo "--- 3b. Kiểm tra retry config trong Envoy ---"
if [[ -n "$NGINX_POD" ]]; then
  kubectl exec -n $NAMESPACE $NGINX_POD -c istio-proxy -- pilot-agent request GET config_dump 2>/dev/null | grep -A5 "retry_policy" | head -20 || true
fi
echo ""

echo "--- 3c. Envoy access logs (xem retry attempts) ---"
if [[ -n "$CART_POD" ]]; then
  kubectl logs $CART_POD -n $NAMESPACE -c istio-proxy --tail=20 2>/dev/null || true
fi
echo ""

# -----------------------------------------------
# TEST 4: Retry on real upstream 500
# -----------------------------------------------
echo ">>> TEST 4: Real 500 Retry Evidence"
create_retry_probe

echo "--- 4a. Probe pod log before request ---"
kubectl logs -n "$NAMESPACE" mesh-retry-probe --tail=5 2>/dev/null || true
echo ""

echo "--- 4b. Call probe service once from mesh-test-nginx ---"
STATUS=$(http_status_from_pod mesh-test-nginx http://mesh-retry-probe:80/)
echo "HTTP Status: ${STATUS:-failed}"
if [[ "$STATUS" == "500" ]]; then
  echo "RESULT: UPSTREAM ERROR (500) - expected"
else
  echo "RESULT: unexpected status ${STATUS:-unknown}"
fi
echo ""

echo "--- 4c. Probe pod logs after request ---"
kubectl logs -n "$NAMESPACE" mesh-retry-probe --tail=20 2>/dev/null || true
echo ""

echo "=============================================="
echo "  TEST COMPLETED"
echo "=============================================="