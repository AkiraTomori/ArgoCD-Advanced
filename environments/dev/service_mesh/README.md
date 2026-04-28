# Yas Dev Service Mesh

This folder contains dev-only Istio manifests for the `yas-dev` namespace.

## Goal
- Enable mTLS in `yas-dev`
- Apply service-to-service authorization policies
- Add retry/timeout policy for selected routes
- Use Kiali to observe the topology

## Suggested rollout order
1. Install Istio control plane and Kiali in the cluster.
2. Label `yas-dev` for sidecar injection.
3. Apply namespace-wide `PeerAuthentication` with `STRICT` mTLS.
4. Apply `AuthorizationPolicy` per workload.
5. Apply `VirtualService` and `DestinationRule` for retry/timeout.
6. Open Kiali and capture the topology screenshot.
7. Run curl tests from a pod inside the cluster.

## Files
- `istio/peer-authentication.yaml`: namespace-wide mTLS policy
- `istio/destination-rules.yaml`: in-mesh TLS defaults
- `istio/authorization-policy.yaml`: allow-list policy examples
- `istio/virtual-service-retry.yaml`: retry and timeout example
- `istio/namespace-label.md`: reminder for namespace injection

## Notes
- Keep these manifests scoped to `yas-dev` only.
- If you want a deny test, add one pod/service account that is not listed in the allow policy and curl from there.
- For a valid topology screenshot, make sure the services that should appear in Kiali have sidecars injected.
