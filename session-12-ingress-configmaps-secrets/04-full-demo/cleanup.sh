#!/usr/bin/env bash
# Session 12 - tear down every resource created by run-demo.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Deleting Ingress"
kubectl delete -f "$DIR/ingress.yaml"  --ignore-not-found
echo "==> Deleting frontend"
kubectl delete -f "$DIR/frontend.yaml" --ignore-not-found
echo "==> Deleting backend"
kubectl delete -f "$DIR/backend.yaml"  --ignore-not-found
echo "==> Deleting Secret"
kubectl delete -f "$DIR/secret.yaml"   --ignore-not-found
echo "==> Deleting ConfigMap"
kubectl delete -f "$DIR/configmap.yaml" --ignore-not-found

echo
echo "==> Remaining resources with label app=yatri-app:"
kubectl get configmap,secret,ingress,deploy,svc,pods -l app=yatri-app
