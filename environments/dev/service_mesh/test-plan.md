# Service Mesh Test Plan for `yas-dev`

## Mục tiêu kiểm thử
- mTLS giữa các service trong `yas-dev`.
- AuthorizationPolicy: chỉ `storefront-bff` và `nginx` được phép gọi `media`, `payment`, `order`.
- Retry policy: upstream trả `500` thì Envoy retry tự động.
- Kiali: chụp topology để minh chứng luồng traffic.

## Kịch bản ngắn
1. Kiểm tra namespace đã bật sidecar injection và pod có `istio-proxy`.
2. Test allow bằng `curl` từ `storefront-bff` hoặc `nginx` tới path thật như `/<service>/v3/api-docs` để nhận `200`.
3. Test deny bằng pod `mesh-debug` để nhận `403`.
4. Test retry bằng `mesh-retry-probe` để thấy request gốc trả `500` và logs có nhiều lần `REQUEST /`.

## Bằng chứng cần nộp
- Ảnh Kiali topology của namespace `yas-dev`.
- Kết quả `curl` cho 3 trạng thái: `200`, `403`, `500`.
- Logs chứng minh retry từ `mesh-retry-probe`.

## Lệnh mẫu
```bash
kubectl exec -n yas-dev <pod-name> -- curl -v http://media.yas-dev.svc.cluster.local/
kubectl exec -n yas-dev mesh-debug -- curl -v http://media.yas-dev.svc.cluster.local/
kubectl -n yas-dev logs mesh-retry-probe --tail=50
```
