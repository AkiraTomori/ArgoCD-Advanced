#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./infrastructure/scripts/switch-active-environment.sh <dev|staging|off>

Description:
  Switches active environment between dev and staging by updating:
  - environments/dev/values-shared.yaml
  - environments/staging/values-shared.yaml
  Or turns both environments off by scaling all replica counts to 0.

Rules:
  - Active env:    backend/ui/replicaCount/reloader replicas = 1
  - Standby env:   backend/ui/replicaCount/reloader replicas = 0

Examples:
  ./infrastructure/scripts/switch-active-environment.sh dev
  ./infrastructure/scripts/switch-active-environment.sh staging
  ./infrastructure/scripts/switch-active-environment.sh off
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

TARGET_ENV="$1"
if [[ "$TARGET_ENV" != "dev" && "$TARGET_ENV" != "staging" && "$TARGET_ENV" != "off" ]]; then
  echo "Error: environment must be 'dev', 'staging', or 'off'."
  usage
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq is required but not installed."
  echo "Install yq: https://github.com/mikefarah/yq"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEV_FILE="$REPO_ROOT/environments/dev/values-shared.yaml"
STAGING_FILE="$REPO_ROOT/environments/staging/values-shared.yaml"

set_replicas() {
  local file="$1"
  local value="$2"

  yq -i ".backend.replicaCount = $value" "$file"
  yq -i ".ui.replicaCount = $value" "$file"
  yq -i ".replicaCount = $value" "$file"
  yq -i ".reloader.reloader.deployment.replicas = $value" "$file"
}

if [[ "$TARGET_ENV" == "dev" ]]; then
  set_replicas "$DEV_FILE" 1
  set_replicas "$STAGING_FILE" 0
elif [[ "$TARGET_ENV" == "staging" ]]; then
  set_replicas "$DEV_FILE" 0
  set_replicas "$STAGING_FILE" 1
else
  set_replicas "$DEV_FILE" 0
  set_replicas "$STAGING_FILE" 0
fi

echo "Switched active environment to '$TARGET_ENV'."
echo "Updated files:"
echo "  - $DEV_FILE"
echo "  - $STAGING_FILE"

echo
echo "Next steps:"
echo "  1) Review: git diff environments/dev/values-shared.yaml environments/staging/values-shared.yaml"
echo "  2) Commit + push"
echo "  3) Sync ArgoCD apps (yas-dev-apps and yas-staging-apps)"
