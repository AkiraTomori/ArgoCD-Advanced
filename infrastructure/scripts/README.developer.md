# Developer Infra Scripts

This folder contains scripts for per-developer test environments used by Jenkins jobs `developer_build` and `developer_destroy`.

## Script: `developer-deploy-infra.sh`

Deploy namespace-scoped infrastructure into a target namespace using charts under `infrastructure/base`:

- postgresql
- pgadmin
- kafka
- elasticsearch
- keycloak
- redis

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

## Notes

- This script intentionally focuses on assignment requirements #4 and #5.
- Observability stack is excluded.
