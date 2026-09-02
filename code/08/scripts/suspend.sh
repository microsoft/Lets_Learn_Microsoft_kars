#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system get \
  "karssandbox/${KARS_SANDBOX_NAME}" -o yaml \
  >"${EVIDENCE_DIR}/pre-suspend-sandbox.yaml"
kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system patch \
  "karssandbox/${KARS_SANDBOX_NAME}" --type=merge \
  -p '{"spec":{"suspended":true}}' >/dev/null
pass "New work is suspended; the KarsSandbox resource and exported evidence remain"
