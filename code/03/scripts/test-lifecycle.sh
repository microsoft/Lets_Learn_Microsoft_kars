#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

"${LAB_ROOT}/scripts/render.sh" >/dev/null
v1="${GENERATED_DIR}/contract-v1.yaml"
v2="${GENERATED_DIR}/contract-v2.yaml"

kubectl apply --server-side --field-manager="${FIELD_MANAGER}" -f "${v1}" >/dev/null
wait_for_sandbox forge-contract Running

kubectl -n kars-system get karssandbox forge-contract --show-managed-fields -o json \
  >"${EVIDENCE_DIR}/contract-v1-sandbox.json"
kubectl -n kars-system get inferencepolicy forge-contract-inference -o json \
  >"${EVIDENCE_DIR}/contract-v1-policy.json"

generation_v1="$(jq -r '.metadata.generation' "${EVIDENCE_DIR}/contract-v1-sandbox.json")"
observed_v1="$(jq -r '.status.observedGeneration' "${EVIDENCE_DIR}/contract-v1-sandbox.json")"
[[ "${generation_v1}" == "${observed_v1}" ]] \
  || fail "V1 status does not observe the current generation"
pass "V1 reached Running with generation=${generation_v1} observedGeneration=${observed_v1}"

jq -e --arg manager "${FIELD_MANAGER}" \
  '.metadata.managedFields[] | select(.manager == $manager and .operation == "Apply")' \
  "${EVIDENCE_DIR}/contract-v1-sandbox.json" >/dev/null \
  || fail "Server-side apply field manager was not recorded"
pass "Kubernetes records ${FIELD_MANAGER} as a field owner"

jq -e '.metadata.finalizers | index("kars.azure.com/namespace-cleanup") != null' \
  "${EVIDENCE_DIR}/contract-v1-sandbox.json" >/dev/null \
  || fail "KARS namespace cleanup finalizer is missing"
pass "KARS finalizer is attached to the owner resource"

namespace="$(jq -r '.status.namespace' "${EVIDENCE_DIR}/contract-v1-sandbox.json")"
kubectl -n "${namespace}" get deployment forge-contract -o json \
  >"${EVIDENCE_DIR}/contract-v1-deployment.json"
pass "Controller generated namespace ${namespace} and Deployment/forge-contract"

set +e
kubectl diff --server-side --field-manager="${FIELD_MANAGER}" -f "${v1}" \
  >"${EVIDENCE_DIR}/contract-v1.diff"
diff_rc=$?
set -e
[[ ${diff_rc} -eq 0 ]] || fail "Applied V1 contract is not idempotent"
pass "kubectl diff reports no drift after V1 apply"

set +e
kubectl diff --server-side --field-manager="${FIELD_MANAGER}" -f "${v2}" \
  >"${EVIDENCE_DIR}/contract-v1-to-v2.diff"
change_rc=$?
set -e
[[ ${change_rc} -eq 1 ]] || fail "kubectl diff did not report the V1 to V2 contract change"
grep -q 'perRequestTokens' "${EVIDENCE_DIR}/contract-v1-to-v2.diff" \
  || fail "V1 to V2 diff does not show the inference budget change"
pass "kubectl diff exposes the pending authority and instruction changes"

set +e
cat <<'EOF' | kubectl apply --server-side \
  --field-manager=agent-self-modification -f - \
  >"${EVIDENCE_DIR}/self-modified-authority.txt" 2>&1
apiVersion: kars.azure.com/v1alpha1
kind: KarsSandbox
metadata:
  name: forge-contract
  namespace: kars-system
spec:
  inferenceRef:
    name: intentionally-missing-policy
EOF
self_modify_rc=$?
set -e
[[ ${self_modify_rc} -ne 0 ]] \
  || fail "An unreviewed field manager changed the Sandbox authority"
grep -qi 'conflict' "${EVIDENCE_DIR}/self-modified-authority.txt" \
  || fail "Self-modification failed for an unexpected reason"
pass "Server-side field ownership rejects an Agent-style authority self-modification"

kubectl apply --server-side --field-manager="${FIELD_MANAGER}" -f "${v2}" >/dev/null
wait_for_sandbox forge-contract Running
kubectl -n kars-system get karssandbox forge-contract -o json \
  >"${EVIDENCE_DIR}/contract-v2-sandbox.json"
kubectl -n kars-system get inferencepolicy forge-contract-inference -o json \
  >"${EVIDENCE_DIR}/contract-v2-policy.json"

generation_v2="$(jq -r '.metadata.generation' "${EVIDENCE_DIR}/contract-v2-sandbox.json")"
observed_v2="$(jq -r '.status.observedGeneration' "${EVIDENCE_DIR}/contract-v2-sandbox.json")"
(( generation_v2 > generation_v1 )) || fail "V2 did not increment metadata.generation"
[[ "${generation_v2}" == "${observed_v2}" ]] \
  || fail "V2 status does not observe the current generation"
pass "V2 incremented generation and reconciliation caught up"

[[ "$(jq -r '.spec.tokenBudget.perRequestTokens' "${EVIDENCE_DIR}/contract-v2-policy.json")" == "2048" ]] \
  || fail "V2 inference budget was not applied"
pass "Git-reviewed inference budget change is visible in the owner policy"

kubectl -n kars-system patch karssandbox forge-contract --type=merge \
  -p '{"spec":{"inferenceRef":{"name":"intentionally-missing-policy"}}}' >/dev/null
wait_for_sandbox forge-contract Degraded
kubectl -n kars-system get karssandbox forge-contract -o json \
  >"${EVIDENCE_DIR}/contract-missing-policy.json"

reason="$(jq -r '.status.conditions[] | select(.type == "Degraded") | .reason' \
  "${EVIDENCE_DIR}/contract-missing-policy.json")"
[[ "${reason}" == "InferencePolicyNotFound" ]] \
  || fail "Unexpected missing-policy reason: ${reason}"
pass "Owner Condition identifies the missing InferencePolicy"

kubectl apply --server-side --force-conflicts \
  --field-manager="${FIELD_MANAGER}" -f "${v2}" >/dev/null
wait_for_sandbox forge-contract Running
kubectl -n kars-system get karssandbox forge-contract -o json \
  >"${EVIDENCE_DIR}/contract-recovered.json"
pass "Restoring the reviewed manifest returns the Sandbox to Running"
