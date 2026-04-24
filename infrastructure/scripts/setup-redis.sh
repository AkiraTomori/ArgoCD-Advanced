#!/bin/bash
set -x

# Read configuration value from cluster-config.yaml file
read -rd '' REDIS_PASSWORD \
< <(yq -r '.redis.password' ./cluster-config.yaml)

helm install redis \
  --set auth.password="$REDIS_PASSWORD" \
  --set architecture=replication \
  --set replica.replicaCount=1 \
  --set master.persistence.enabled=true \
  --set master.podSecurityContext.fsGroup=1001 \
  --set master.containerSecurityContext.runAsUser=1001 \
  --set volumePermissions.enabled=true \
  --set master.resources.requests.cpu="100m" \
  --set master.resources.requests.memory="256Mi" \
  --set master.resources.limits.cpu="500m" \
  --set master.resources.limits.memory="512Mi" \
  --set replica.resources.requests.cpu="100m" \
  --set replica.resources.requests.memory="256Mi" \
  --set replica.resources.limits.cpu="500m" \
  --set replica.resources.limits.memory="512Mi" \
  oci://registry-1.docker.io/bitnamicharts/redis -n redis --create-namespace
