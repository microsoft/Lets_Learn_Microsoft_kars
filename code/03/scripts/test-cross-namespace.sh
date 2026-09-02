#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

"${LAB_ROOT}/scripts/render.sh" >/dev/null
manifest="${GENERATED_DIR}/cross-namespace.yaml"

cleanup() {
  kubectl -n kars-system delete karssandbox forge-cross-namespace \
    --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl delete namespace code03-policy-other \
    --ignore-not-found --wait=true >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply --server-side --field-manager="${FIELD_MANAGER}" -f "${manifest}" >/dev/null
wait_for_sandbox forge-cross-namespace Degraded
kubectl -n kars-system get karssandbox forge-cross-namespace -o json \
  >"${EVIDENCE_DIR}/cross-namespace-sandbox.json"

reason="$(jq -r '.status.conditions[] | select(.type == "Degraded") | .reason' \
  "${EVIDENCE_DIR}/cross-namespace-sandbox.json")"
message="$(jq -r '.status.conditions[] | select(.type == "Degraded") | .message' \
  "${EVIDENCE_DIR}/cross-namespace-sandbox.json")"
[[ "${reason}" == "InferencePolicyNotFound" ]] \
  || fail "Unexpected cross-namespace reason: ${reason}"
[[ "${message}" == *"cross-namespace refs not supported"* ]] \
  || fail "Condition did not explain the same-namespace rule"
pass "Cross-namespace policy reference is Degraded with an actionable Condition"

if kubectl get namespace kars-forge-cross-namespace >/dev/null 2>&1; then
  fail "Controller created a workload namespace for a Degraded contract"
fi
pass "No workload namespace or Pod is created for the unresolved contract"
