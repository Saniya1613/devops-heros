#!/usr/bin/env bash
# Session 12 - end-to-end automated deployment of the Yatri multi-tier stack
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/6] Applying ConfigMap (non-sensitive configuration)"
kubectl apply -f "$DIR/configmap.yaml"

echo "==> [2/6] Applying Secret (sensitive credentials)"
kubectl apply -f "$DIR/secret.yaml"

echo "==> [3/6] Deploying backend Deployment + ClusterIP Service"
kubectl apply -f "$DIR/backend.yaml"

echo "==> [4/6] Deploying frontend Deployment + ClusterIP Service"
kubectl apply -f "$DIR/frontend.yaml"

echo "==> [5/6] Applying Ingress (L7 path-based routing)"
kubectl apply -f "$DIR/ingress.yaml"

echo "==> [6/6] Waiting for rollouts to finish"
kubectl rollout status deployment/yatri-backend  --timeout=180s
kubectl rollout status deployment/yatri-frontend --timeout=180s

echo
echo "==> Stack is up:"
kubectl get configmap,secret,ingress,deploy,svc,pods -l app=yatri-app
