#!/bin/bash
set -e
set -x

echo "Preparing Redis Helm Repo..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update