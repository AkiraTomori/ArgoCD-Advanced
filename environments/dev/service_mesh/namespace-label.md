# Namespace Label

Gắn sidecar cho `yas-dev`:

```bash
kubectl label namespace yas-dev istio-injection=enabled --overwrite
```

Kiểm tra nhanh:

```bash
kubectl get ns yas-dev --show-labels
kubectl get pods -n yas-dev -o wide
```

Ghi chú: nếu cluster dùng revision-based injection thì thay label cho đúng revision.
