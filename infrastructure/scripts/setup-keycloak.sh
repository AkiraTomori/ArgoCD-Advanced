
#!/bin/bash
set -x

#Read configuration value from cluster-config.yaml file
read -rd '' DOMAIN POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
BOOTSTRAP_ADMIN_USERNAME BOOTSTRAP_ADMIN_PASSWORD \
KEYCLOAK_BACKOFFICE_REDIRECT_URL KEYCLOAK_STOREFRONT_REDIRECT_URL \
< <(yq -r '.domain,
  .postgresql.username, .postgresql.password,
  .keycloak.bootstrapAdmin.username, .keycloak.bootstrapAdmin.password,
  .keycloak.backofficeRedirectUrl, .keycloak.storefrontRedirectUrl' ./cluster-config.yaml)

#Install CRD keycloak
kubectl create namespace keycloak
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n keycloak

# Install keycloak
helm upgrade --install keycloak ./keycloak/keycloak \
--namespace keycloak \
--set hostname="identity.$DOMAIN" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set bootstrapAdmin.username="$BOOTSTRAP_ADMIN_USERNAME" \
--set bootstrapAdmin.password="$BOOTSTRAP_ADMIN_PASSWORD" \
--set backofficeRedirectUrl="$KEYCLOAK_BACKOFFICE_REDIRECT_URL" \
--set storefrontRedirectUrl="$KEYCLOAK_STOREFRONT_REDIRECT_URL"

# Sync redirect URIs for existing clients to avoid stale values from previous imports.
kubectl wait --for=condition=Ready pod/keycloak-0 -n keycloak --timeout=300s
kubectl exec -n keycloak keycloak-0 -- sh -s -- \
    "$BOOTSTRAP_ADMIN_USERNAME" \
    "$BOOTSTRAP_ADMIN_PASSWORD" \
    "$KEYCLOAK_BACKOFFICE_REDIRECT_URL" \
    "$KEYCLOAK_STOREFRONT_REDIRECT_URL" \
    "http://api.$DOMAIN" <<'EOF'
# set -eu

# admin_user="$1"
# admin_password="$2"
# backoffice_redirect_url="$3"
# storefront_redirect_url="$4"
# swagger_redirect_url="$5"

# /opt/keycloak/bin/kcadm.sh config credentials \
#     --server http://keycloak-service \
#     --realm master \
#     --user "$admin_user" \
#     --password "$admin_password" >/dev/null

# backoffice_client_id=$(/opt/keycloak/bin/kcadm.sh get clients -r Yas -q clientId=backoffice-bff --fields id --format csv --noquotes | tail -n 1)
# storefront_client_id=$(/opt/keycloak/bin/kcadm.sh get clients -r Yas -q clientId=storefront-bff --fields id --format csv --noquotes | tail -n 1)
# swagger_client_id=$(/opt/keycloak/bin/kcadm.sh get clients -r Yas -q clientId=swagger-ui --fields id --format csv --noquotes | tail -n 1)

# if [ -n "$backoffice_client_id" ]; then
#     /opt/keycloak/bin/kcadm.sh update "clients/$backoffice_client_id" -r Yas \
#         -s "redirectUris=[\"${backoffice_redirect_url}/*\",\"http://localhost:3000/*\",\"http://localhost:8087/*\"]"
# fi

# if [ -n "$storefront_client_id" ]; then
#     /opt/keycloak/bin/kcadm.sh update "clients/$storefront_client_id" -r Yas \
#         -s "redirectUris=[\"${storefront_redirect_url}/*\",\"http://localhost:8087/*\"]"
# fi

# if [ -n "$swagger_client_id" ]; then
#     /opt/keycloak/bin/kcadm.sh update "clients/$swagger_client_id" -r Yas \
#     -s "redirectUris=[\"${swagger_redirect_url}/*\",\"http://localhost:8081/*\",\"http://localhost:8092/*\",\"http://localhost:8080/*\",\"http://localhost:8091/*\",\"http://localhost:8083/*\",\"http://localhost:8093/*\",\"http://localhost:8090/*\",\"http://localhost:8089/*\",\"http://localhost:8088/*\",\"http://localhost:8085/*\",\"http://localhost:8084/*\",\"http://localhost:8086/*\"]" \
#     -s "webOrigins=[\"http://localhost:8088\",\"http://localhost:8089\",\"http://localhost:8084\",\"http://localhost:8083\",\"http://localhost:8086\",\"${swagger_redirect_url}\",\"http://localhost:8085\",\"http://localhost:8080\",\"http://localhost:8091\",\"http://localhost:8090\",\"http://localhost:8093\",\"http://localhost:8081\",\"http://localhost:8092\"]"
# fi
# EOF
