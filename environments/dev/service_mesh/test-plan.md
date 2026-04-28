# Service Mesh Test Plan for yas-dev

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
- `storefront-bff` -> `product`

Expected:
- curl returns `200` or the application response.

## 3. AuthorizationPolicy deny test
Goal: a non-allowed pod/service account is blocked.

Example deny case:
- launch a debug pod in `yas-dev` with a different service account
- curl `http://media.yas-dev.svc.cluster.local/`

Expected:
- request is rejected by Istio authorization, often `403`.

## 4. Retry test
Goal: confirm retry policy is active on 5xx errors.

Example:
- apply a `VirtualService` with retry on `5xx`
- temporarily make the upstream return `500`

Expected:
- repeated attempts are visible in logs
- client receives a final response after retry attempts

## Example curl
```bash
kubectl exec -n yas-dev <pod-name> -- curl -v http://media.yas-dev.svc.cluster.local/
```

## Evidence to collect
- Kiali topology screenshot
- `kubectl logs` from the calling pod
- curl output showing allow or deny
- retry evidence from service logs
