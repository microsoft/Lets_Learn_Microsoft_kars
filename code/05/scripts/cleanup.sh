#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl --context kind-kars-dev -n kars-system delete \
  "karssandbox/${SANDBOX_NAME}" \
  inferencepolicy/forge-byo-inference \
  --ignore-not-found \
  --wait=false
pass "Requested cleanup of code/05 Kubernetes resources"
