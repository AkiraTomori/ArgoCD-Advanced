# Namespace Label

Enable sidecar injection for `yas-dev`:

```bash
kubectl label namespace yas-dev istio-injection=enabled --overwrite
```

Verify:

```bash
kubectl get ns yas-dev --show-labels
kubectl get pods -n yas-dev -o wide
```

If your Istio installation uses revision-based injection, replace the label above with the revision label used by your cluster.

Current scenario focus:
- allowed callers: `storefront-bff`, `nginx`
- protected services: `media`, `payment`, `order`
- deny test caller: `mesh-debug`
