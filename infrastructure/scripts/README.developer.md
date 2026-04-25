# Developer Infra Scripts

This folder contains scripts for per-developer test environments used by Jenkins jobs `developer_build` and `developer_destroy`.

## Script: `developer-deploy-infra.sh`

Deploy namespace-scoped infrastructure into a single target namespace using scripts under `infrastructure/scripts`:

- setup-keycloak.sh
- setup-redis.sh
- setup-cluster.sh

### Required env vars

- `TARGET_NAMESPACE`: destination namespace, for example `test-alice-tax`

### Optional env vars

- `INSTALL_OPERATORS`: `true|false` (default `false`)
- `VALUES_FILE`: shared values file (default `environments/test/values-shared.yaml`)

### Example

```bash
TARGET_NAMESPACE=test-alice-tax \
INSTALL_OPERATORS=false \
bash infrastructure/scripts/developer-deploy-infra.sh
```

## Recommended deployment order (single namespace)

For step-by-step deployment, follow this sequence:

1. Install Keycloak

```bash
./setup-keycloak.sh
```

2. Install Redis

```bash
./setup-redis.sh
```

3. Install cluster infrastructure (PostgreSQL, Kafka, Elasticsearch, Observability)

```bash
./setup-cluster.sh
```

4. Deploy YAS configuration

```bash
./deploy-yas-configuration.sh
```

Keycloak may temporarily CrashLoopBackOff before PostgreSQL is running. This is expected. After PostgreSQL is healthy, Keycloak should recover automatically.

All infrastructure components are deployed into the same namespace provided by `TARGET_NAMESPACE`.

## Safe Minikube Restart

To avoid recurrent CrashLoopBackOff after `minikube stop/start` (especially on Kafka and Elasticsearch), use:

```bash
./minikube-start-safe.sh
```

What this script does:

- Starts minikube (can be skipped with `START_CLUSTER=false`)
- Waits for nodes to become Ready
- Detects known Kafka crash signature (`Invalid cluster.id`) and auto-heals storage path/PVC
- Detects known Elasticsearch lock/permission signature (`node.lock`, `AccessDeniedException`) and auto-heals storage path
- Prints final status for Kafka and Elasticsearch pods

Examples:

```bash
# Start cluster and run self-heal checks
./minikube-start-safe.sh

# If minikube is already started
START_CLUSTER=false ./minikube-start-safe.sh

# Use a non-default minikube profile
MINIKUBE_PROFILE=my-profile ./minikube-start-safe.sh
```

## Notes

- This script intentionally focuses on assignment requirements #4 and #5.
- Observability components are installed by `setup-cluster.sh`.
