# Service Mesh Test Plan for yas-dev

## 0. Bối cảnh test 3 service
- `storefront-bff` và `nginx` là service được phép gọi.
- `media`, `order`, `payment` là 3 service được bảo vệ.
- `mesh-debug` là pod/service account dùng để test deny.

Kỳ vọng mặc định: chỉ `storefront-bff` và `nginx` được phép gọi vào cả 3 service. Các caller khác sẽ bị chặn.

## 0. Pre-check
Goal: ensure namespace and sidecar injection are ready.

Checks:
- `kubectl get ns yas-dev --show-labels`
- `kubectl get pod -n yas-dev -o wide`
- Confirm target pods have the `istio-proxy` sidecar.

## 1. mTLS
Goal: confirm traffic between meshed services uses STRICT mTLS.

Checks:
- Apply `PeerAuthentication` in `yas-dev`.
- Confirm Istio sidecars are injected into target pods.
- Use Kiali to verify service-to-service edges.

## 2. AuthorizationPolicy allow test
Goal: only allowed workloads can call the protected service.

Example allow case:
- `storefront-bff` -> `media`
- `nginx` -> `media`
- `storefront-bff` -> `order`
- `nginx` -> `order`
- `storefront-bff` -> `payment`
- `nginx` -> `payment`

Expected:
- curl returns `200` or the application response.
- traffic is accepted only when the source service account matches `cluster.local/ns/yas-dev/sa/storefront-bff` or `cluster.local/ns/yas-dev/sa/nginx` for the 3 protected services.

Allow matrix:
- `media`: `storefront-bff`, `nginx`
- `payment`: `storefront-bff`, `nginx`
- `order`: `storefront-bff`, `nginx`

## 3. AuthorizationPolicy deny test
Goal: a non-allowed pod/service account is blocked.

Example deny case:
- create a debug pod in `yas-dev` using a service account that is not allow-listed, for example `mesh-debug`
- curl `http://media.yas-dev.svc.cluster.local/`, `http://order.yas-dev.svc.cluster.local/`, và `http://payment.yas-dev.svc.cluster.local/` from that pod

Example nginx test:
- exec into the `nginx` pod in namespace `yas-dev`
- curl `http://media.yas-dev.svc.cluster.local/`, `http://order.yas-dev.svc.cluster.local/`, and `http://payment.yas-dev.svc.cluster.local/`

Expected nginx result:
- requests are allowed and return the upstream responses

Expected:
- request is rejected by Istio authorization, often `403`.
- Kiali should still show the edge, but the request will be blocked by policy.

## 4. Retry test
Goal: confirm retry policy is active on 5xx errors.

Example:
- apply the `VirtualService` with retry on `5xx`
- temporarily make the upstream return `500`, or point the route to a test endpoint that returns `500`

Expected:
- repeated attempts are visible in logs
- client receives a final response after retry attempts

## 5. Kiali topology evidence
Goal: capture the service mesh graph for `yas-dev`.

Checks:
- open Kiali and select namespace `yas-dev`
- confirm topology edges for `storefront-bff/nginx -> media/order/payment`
- capture a screenshot after one successful request

## Example curl
```bash
kubectl exec -n yas-dev <pod-name> -- curl -v http://media.yas-dev.svc.cluster.local/
```

## Example deny pod
```bash
kubectl apply -n yas-dev -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: mesh-debug
spec:
  serviceAccountName: mesh-debug
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      command: ["sh", "-c", "sleep 3600"]
EOF

kubectl exec -n yas-dev mesh-debug -- curl -v http://media.yas-dev.svc.cluster.local/
```

## Evidence to collect
- Kiali topology screenshot
- `kubectl logs` from the calling pod
- curl output showing allow or deny
- retry evidence from service logs
