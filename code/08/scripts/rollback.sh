#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ "${ROLLBACK_IMAGE}" == *.azurecr.io/*@sha256:* ]] \
  || fail "Set ROLLBACK_IMAGE to the previously approved ACR digest"
kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system set env \
  deployment/kars-controller "MAF_RUNTIME_IMAGE=${ROLLBACK_IMAGE}" >/dev/null
kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system rollout status \
  deployment/kars-controller --timeout=5m >/dev/null
kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system annotate \
  "karssandbox/${KARS_SANDBOX_NAME}" \
  "forge.bytecraft.dev/maf-runtime-rollback=$(date -u +%Y%m%dT%H%M%SZ)" \
  --overwrite >/dev/null
pass "MAF runtime rollback was applied; verify the Sandbox phase and run make verify"
