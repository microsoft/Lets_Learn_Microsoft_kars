#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

for sandbox in forge-contract forge-cross-namespace forge-invalid-provider; do
  kubectl -n kars-system delete karssandbox "${sandbox}" \
    --ignore-not-found --wait=true >/dev/null
done

for policy in \
  forge-contract-inference \
  forge-invalid-provider-inference; do
  kubectl -n kars-system delete inferencepolicy "${policy}" \
    --ignore-not-found >/dev/null
done

kubectl delete namespace code03-policy-other \
  --ignore-not-found --wait=true >/dev/null

for namespace in \
  kars-forge-contract \
  kars-forge-cross-namespace \
  kars-forge-invalid-provider; do
  kubectl wait --for=delete "namespace/${namespace}" --timeout=120s \
    >/dev/null 2>&1 || true
done

echo "Removed code/03 Kubernetes resources. Local evidence was preserved."
