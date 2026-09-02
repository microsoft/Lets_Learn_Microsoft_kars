#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

name="forge-missing-policy"
manifest="${LAB_ROOT}/manifests/missing-inference-policy.yaml"

cleanup() {
  kubectl -n kars-system delete karssandbox "${name}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f "${manifest}" >/dev/null

phase=""
for _ in $(seq 1 30); do
  phase="$(kubectl -n kars-system get karssandbox "${name}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Degraded" ]] && break
  sleep 2
done

kubectl -n kars-system get karssandbox "${name}" -o json \
  >"${EVIDENCE_DIR}/missing-policy-sandbox.json"

[[ "${phase}" == "Degraded" ]] || fail "Missing-policy sandbox did not become Degraded"
reason="$(jq -r '.status.conditions[] | select(.type == "Degraded") | .reason' \
  "${EVIDENCE_DIR}/missing-policy-sandbox.json")"
[[ "${reason}" == "InferencePolicyNotFound" ]] \
  || fail "Unexpected degradation reason: ${reason}"
pass "Missing InferencePolicy produces Degraded/InferencePolicyNotFound"
